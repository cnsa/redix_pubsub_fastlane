defmodule Redix.PubSub.Fastlane.Server do
  @moduledoc false

  use GenServer
  require Logger

  @redix_opts [:host, :port, :password, :database]
  @unsubscribed_callbacks [:unsubscribed, :punsubscribed]
  @subscribed_callbacks [:subscribed, :psubscribed]

  defmodule Subscription do
    @moduledoc false
    defstruct parent: nil, options: [], pid: nil
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
    channels = :ets.new(opts[:server_name], [:named_table, :duplicate_bag,
                                             read_concurrency: true, write_concurrency: true])

    Process.flag(:trap_exit, true)
    state = %{server_name: Keyword.fetch!(opts, :server_name),
              channels: channels,
              opts: opts,
              connected: false,
              monitors: %{},
              pool_name: Keyword.fetch!(opts, :pool_name),
              namespace: Keyword.fetch!(opts, :namespace),
              decoder: Keyword.fetch!(opts, :decoder),
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
  # Debug method, don't use it in Production.
  def list(pubsub_server, channel), do: GenServer.call(pubsub_server, {:list, channel})

  @doc false
  def subscribe(pubsub_server, from, channel, fastlane) do
    GenServer.cast(pubsub_server, {:subscribe, from, channel, %{fastlane: fastlane, method: :subscribe}})
    :ok
  end

  @doc false
  def psubscribe(pubsub_server, from, pattern, fastlane) do
    GenServer.cast(pubsub_server, {:subscribe, from, pattern, %{fastlane: fastlane, method: :psubscribe}})
    :ok
  end

  @doc false
  def unsubscribe(pubsub_server, from, channel) do
    GenServer.cast(pubsub_server, {:unsubscribe, from, channel, :unsubscribe})
    :ok
  end

  @doc false
  def punsubscribe(pubsub_server, from, pattern) do
    GenServer.cast(pubsub_server, {:unsubscribe, from, pattern, :punsubscribe})
    :ok
  end

  @doc false
  def publish(pubsub_server, channel, message) do
    GenServer.call(pubsub_server, {:publish, channel, message})
    :ok
  end

  def handle_call(:lookup, _from, state) do
    {:reply, self(), state}
  end

  def handle_call({:find, channel}, {from, _ref}, %{channels: channels} = state) do
    result = _find(channels, channel, from)

    {:reply, result, state}
  end

  def handle_call({:list, channel}, _from, %{channels: channels} = state) do
    result = _list(channels, channel)

    {:reply, result, state}
  end

  def handle_call({:publish, channel, message}, _from, state) do
    result = include_ns(channel, state)
    |> _publish(message, state.pool_name)

    {:reply, result, state}
  end

  def handle_cast({:monitor, pid}, state) do
    {:noreply, put_new_monitor(state, pid)}
  end

  def handle_cast({:demonitor, pid}, state) do
    {:noreply, drop_monitor(state, pid)}
  end

  def handle_cast({:subscribe, from, channel, opts}, %{redix_pid: _} = state) do
    :ok = GenServer.cast(state.server_name, {:monitor, from})
    _subscribe(from, channel, state, opts)
    {:noreply, state}
  end

  def handle_cast({:unsubscribe, from, channel, method}, %{redix_pid: _} = state) do
    _unsubscribe(from, channel, state, method)
    {:noreply, state}
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

  def handle_info({:DOWN, _ref, _type, pid, _info}, state) do
    _unsubscribe(pid, state)
    {:noreply, drop_monitor(state, pid)}
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
     payload =
      exclude_ns(message, state)
       |> decode_payload(state)

     if is_nil(state.fastlane) do
       _notify_all_embed(subscribers, payload)
     else
       state.fastlane.fastlane(subscribers, payload)
     end
  end

  defp _notify_all_embed(subscribers, message) do
     subscribers
     |> Enum.each(fn
       {_from, {pid, parent, options}} ->
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
      |> Enum.map(fn {_, {_, {pid, parent, options}}} ->
        %{ id: channel,
           from: from,
           fastlane: %Subscription{pid: pid, parent: parent, options: options}}
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

  defp _subscribe(from, channel, state, opts) do
    true = :ets.insert(state.channels, {channel, {from, opts[:fastlane]}})

    case subscribe_to_channel(state, channel, opts[:method]) do
      :error -> :error
      _      -> :ok
    end
  end

  defp _unsubscribe(from, channel, %{channels: channels} = state, method) do
    true = :ets.match_delete(channels, {channel, {from, :_}})

    case :ets.select_count(channels, [{{channel, :_}, [], [true]}]) do
      0 ->
        unsubscribe_from_channel(channel, state, method)
        :ok = GenServer.cast(state.server_name, {:demonitor, from})
      _ -> :ok
    end
  end
  defp _unsubscribe(_, _, _, _), do: :error
  defp _unsubscribe(from, %{channels: channels}) do
    true = :ets.match_delete(channels, {:_, {from, :_}})
  end

  defp _unsubscribe_all(channel, %{channels: channels}) do
    true = :ets.delete(channels, channel)
  end

  defp unsubscribe_from_channel(channel, %{connected: true, redix_pid: redix_pid} = state, method) do
    apply(Redix.PubSub, method, [redix_pid, include_ns(channel, state), self()])
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

  defp decode_payload(%{payload: payload} = message, %{decoder: decoder}) do
    %{message | payload: decoder.(payload) }
  end
  defp decode_payload(message, _), do: message

  # Monitor handlers

  defp put_new_monitor(%{monitors: monitors} = state, pid) do
    case Map.fetch(monitors, pid) do
      {:ok, _ref} -> state
      :error -> %{state | monitors: Map.put(monitors, pid, Process.monitor(pid))}
    end
  end

  defp drop_monitor(%{monitors: monitors} = state, pid) do
    case Map.fetch(monitors, pid) do
      {:ok, ref} ->
        Process.demonitor(ref)
        %{state | monitors: Map.delete(monitors, pid)}
      :error -> state
    end
  end

  # Connection handler

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
