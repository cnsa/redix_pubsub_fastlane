defmodule Redix.PubSub.Fastlane.Server do
  @moduledoc false

  use GenServer
  require Logger

  @redix_opts [:host, :port, :password, :database]
  @unsubscribed_callbacks [:unsubscribed, :punsubscribed]
  @subscribed_callbacks [:subscribed, :psubscribed]

  defmodule Subscription do
    @moduledoc false
    defstruct parent: nil, options: [], channel: nil, pid: nil
  end

  @doc """
  Starts the server
  """
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: Dict.fetch!(opts, :server_name))
  end

  @doc """
  Initializes the server.
  """
  def init(opts) do
    Process.flag(:trap_exit, true)
    channels = :ets.new(opts[:server_name], [:named_table, :duplicate_bag, {:read_concurrency, true}, {:write_concurrency, true}])

    state = %{server_name: Keyword.fetch!(opts, :server_name),
              channels: channels,
              opts: opts,
              connected: false,
              pool_name: Keyword.fetch!(opts, :pool_name),
              namespace: Keyword.fetch!(opts, :namespace),
              fastlane: Keyword.fetch!(opts, :fastlane),
              redix_pid: nil}

    {:ok, establish_conn(state)}
  end

  @doc false
  def lookup(pubsub_server), do: GenServer.call(pubsub_server, :lookup)

  @doc false
  def stop(pubsub_server), do: GenServer.cast(pubsub_server, :stop)

  @doc false
  # Debug method, don't use it in Production.
  def find(pubsub_server, channel), do: GenServer.call(pubsub_server, {:find, channel})

  @doc false
  def subscribe(pubsub_server, from, channel, fastlane), do: GenServer.call(pubsub_server, {:subscribe, from, channel, fastlane, :subscribe})

  @doc false
  def psubscribe(pubsub_server, from, pattern, fastlane), do: GenServer.call(pubsub_server, {:subscribe, from, pattern, fastlane, :psubscribe})

  @doc false
  def unsubscribe(pubsub_server, from, channel), do: GenServer.call(pubsub_server, {:unsubscribe, from, channel, :unsubscribe})

  @doc false
  def punsubscribe(pubsub_server, from, pattern), do: GenServer.call(pubsub_server, {:unsubscribe, from, pattern, :punsubscribe})

  @doc false
  def publish(pubsub_server, channel, message), do: GenServer.call(pubsub_server, {:publish, channel, message})

  def handle_call({:publish, channel, message}, _from, state) do
    result =
      include_ns(channel, state)
      |> _publish(message, state.pool_name)

    {:reply, result, state}
  end

  def handle_call(:lookup, _from, state) do
    {:reply, self(), state}
  end

  def handle_call({:find, channel}, {from, _ref}, %{channels: channels} = state) do
    result = _find(channels, channel, from)

    {:reply, result, state}
  end

  def handle_call({:subscribe, from, channel, fastlane, method}, _from, %{redix_pid: _} = state) do
    result = _subscribe(from, channel, fastlane, state, method)
    {:reply, result, state}
  end

  def handle_call({:unsubscribe, from, channel, method}, _from, %{redix_pid: _} = state) do
    result = _unsubscribe(from, channel, state, method)
    {:reply, result, state}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def handle_info({:redix_pubsub, redix_pid, :message, %{channel: channel} = message}, %{channels: channels, redix_pid: redix_pid} = state) do
    broadcast_message(channels, channel, message, state)
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, redix_pid, :pmessage, %{pattern: pattern} = message}, %{channels: channels, redix_pid: redix_pid} = state) do
    broadcast_message(channels, pattern, message, state)
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, redix_pid, :disconnected, _}, %{redix_pid: redix_pid} = state) do
    {:noreply, %{ state | connected: false }}
  end

  def handle_info({:redix_pubsub, redix_pid, operation, _}, %{redix_pid: redix_pid} = state) when operation in @subscribed_callbacks do
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, redix_pid, operation, status}, %{redix_pid: redix_pid} = state) when operation in @unsubscribed_callbacks do
    case status do
      %{pattern: pattern} -> _unsubscribe_all(pattern, state)
      %{channel: channel} -> _unsubscribe_all(channel, state)
    end
    {:noreply, state}
  end

  def handle_info({:EXIT, _, _reason}, state) do
    {:noreply, state}
  end

  @doc """
  Connection establishment and shutdown loop
  On init, an initial conection to redis is attempted when starting `:redix`
  """
  def terminate(_reason, _state) do
    :ok
  end

  defp broadcast_message(channels, channel_w_namespace, message, state) do
    channel = _exclude_ns(channel_w_namespace, state.namespace)

    channels
    |> _list(channel)
    |> _notify_all(message, state)
  end

  defp _notify_all(subscribers, message, state) do
     payload = exclude_ns(message, state)

     if is_nil(state.fastlane) do
       _notify_all_embed(subscribers, payload)
     else
       state.fastlane.fastlane(subscribers, payload)
     end
  end

  defp _notify_all_embed(subscribers, message) do
     subscribers
     |> Enum.each(fn
       {_from, %{pid: pid, options: options, parent: parent}} ->
          parent.fastlane(pid, message, options)
       _ -> :noop
     end)
  end

  defp _find(channels, channel, from) do
    subscriptions =
      :ets.lookup(channels, channel)
      |> Enum.filter(fn
        {^channel, {^from, _}} -> true
        _ -> false
      end)
      |> Enum.map(fn {_, {_, subscription}} ->
        %{ id: channel, from: from, subscription: subscription}
      end)

    case subscriptions do
      [] -> :error
      _ -> {:ok, subscriptions}
    end
  end

  defp _list(channels, channel) do
    try do
      channels
      |> :ets.lookup_element(channel, 2)
    catch
      :error, :badarg -> []
    end
  end

  defp _publish(channel, {serializer, message}, pool_name) when is_function(serializer, 1) do
    _publish_message(channel, serializer.(message), pool_name)
  end
  defp _publish(channel, message, pool_name) do
    _publish_message(channel, message, pool_name)
  end

  defp _publish_message(channel, message, pool_name) do
    :poolboy.transaction pool_name, fn(redix_pid) ->
      case Redix.command(redix_pid, ["PUBLISH", channel, message]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp _subscribe(from, channel, {pid, parent, options}, state, method) when is_atom(parent) and is_list(options)  do
    subscription = %Subscription{pid: pid, parent: parent, options: options, channel: channel}

    true = :ets.insert(state.channels, {channel, {from, subscription}})

    case subscribe_to_channel(state, channel, method) do
      :error -> :error
      _      -> :ok
    end
  end
  defp _subscribe(_, _, _, _, _), do: :error

  defp _unsubscribe(from, channel, %{channels: channels} = state, method) do
    true = :ets.match_delete(channels, {channel, {from, :_}})

    case :ets.select_count(channels, [{{channel, :_}, [], [true]}]) do
      0 -> unsubscribe_from_channel(channel, state, method)
      _ -> :noop
    end
    :ok
  end
  defp _unsubscribe(_, _, _, _), do: :error

  defp _unsubscribe_all(channel, %{channels: channels}) do
    true = :ets.delete(channels, channel)
  end

  defp unsubscribe_from_channel(channel, %{connected: true, redix_pid: redix_pid} = state, method) do
    try do
      apply(Redix.PubSub, method, [redix_pid, include_ns(channel, state), self()])
    catch
      :exit, _ -> :ok
    end
  end
  defp unsubscribe_from_channel(_, _, _), do: :ok

  defp subscribe_to_channel(%{connected: true, redix_pid: redix_pid} = state, channel, method) do
    apply(Redix.PubSub, method, [redix_pid, include_ns(channel, state), self()])
  end
  defp subscribe_to_channel(_, _, _), do: :error

  defp include_ns(name, %{namespace: namespace}) when is_bitstring(namespace) or is_atom(namespace) do
    "#{namespace}.#{name}"
  end
  defp include_ns(name, _), do: name

  defp exclude_ns(%{pattern: pattern, channel: channel} = message, %{namespace: namespace}) do
    %{message | pattern: _exclude_ns(pattern, namespace), channel: _exclude_ns(channel, namespace)}
  end
  defp exclude_ns(%{channel: channel} = message, %{namespace: namespace}) do
    %{message | channel: _exclude_ns(channel, namespace)}
  end
  defp exclude_ns(message, _), do: message

  defp _exclude_ns(name, namespace) when is_bitstring(name) do
    case name |> String.split("#{namespace}.", parts: 2) do
      ["", channel] -> channel
      [_]           -> name
    end
  end
  defp _exclude_ns(name, _), do: name

  defp establish_conn(state) do
    redis_opts = Keyword.take(state.opts, @redix_opts)
    case Redix.PubSub.start_link(redis_opts) do
      {:ok, redix_pid} -> %{state | redix_pid: redix_pid, connected: true}
      {:error, _} ->
        Logger.error("No connection to Redis")
        %{state | connected: false}
    end
  end
end
