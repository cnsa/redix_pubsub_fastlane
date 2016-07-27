defmodule Redix.PubSub.Fastlane.Server do
  @moduledoc false

  use GenServer
  require Logger

  @redix_opts [:host, :port, :password, :database]
  @skip_callbacks [:subscribed, :unsubscribed, :psubscribed, :punsubscribed]

  defmodule Subscription do
    @moduledoc false
    defstruct parent: nil, options: [], channel: nil
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
    channels = :ets.new(opts[:server_name], [:set, :named_table, {:read_concurrency, true}, {:write_concurrency, true}])

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
  def find(pubsub_server, channel), do: GenServer.call(pubsub_server, {:find, channel})

  @doc false
  def subscribe(pubsub_server, channel, fastlane), do: GenServer.call(pubsub_server, {:subscribe, channel, fastlane, :subscribe})

  @doc false
  def psubscribe(pubsub_server, pattern, fastlane), do: GenServer.call(pubsub_server, {:subscribe, pattern, fastlane, :psubscribe})

  @doc false
  def unsubscribe(pubsub_server, channel), do: GenServer.call(pubsub_server, {:unsubscribe, channel, :unsubscribe})

  @doc false
  def punsubscribe(pubsub_server, pattern), do: GenServer.call(pubsub_server, {:unsubscribe, pattern, :punsubscribe})

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

  def handle_call({:find, channel}, _from, %{channels: channels} = state) do
    result = _find(channels, channel)

    {:reply, result, state}
  end

  def handle_call({:subscribe, channel, fastlane, method}, _from, %{channels: channels, redix_pid: _} = state) do
    subscription = case _find(channels, channel) do
      {:ok, _} -> :ok
      :error   -> _subscribe(channel, fastlane, state, method)
    end
    {:reply, subscription, state}
  end

  def handle_call({:unsubscribe, channel, method}, _from, %{channels: channels, redix_pid: _} = state) do
    result = case _find(channels, channel) do
      {:ok, _} -> _unsubscribe(channel, state, method)
      :error   -> :ok
    end
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

  def handle_info({:redix_pubsub, redix_pid, operation, _}, %{redix_pid: redix_pid} = state) when operation in @skip_callbacks do
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
    case _find(channels, channel) do
      {:ok, %{subscription: subscription}} ->
        module = subscription.parent || state.fastlane
        payload = exclude_ns(message, state)
        module.fastlane(payload, subscription.options)
      _ -> nil
    end
  end

  defp _find(channels, channel) do
    case :ets.lookup(channels, channel) do
      [{^channel, subscription}] -> {:ok, %{ id: channel, subscription: subscription}}
      [] -> :error
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

  defp _subscribe(channel, {parent, options}, state, method) when is_atom(parent) and is_list(options)  do
    subscription = %Subscription{parent: parent, options: options, channel: channel}

    case subscribe_to_channel(state, channel, subscription, method) do
      :error -> :error
      _      -> :ok
    end
  end
  defp _subscribe(_, _, _, _), do: :error

  defp _unsubscribe(channel, %{connected: true, redix_pid: redix_pid, channels: channels} = state, method) do
    true = :ets.delete(channels, channel)
    apply(Redix.PubSub, method, [redix_pid, include_ns(channel, state), self()])
    :ok
  end
  defp _unsubscribe(_, _, _), do: :error

  defp subscribe_to_channel(%{connected: true, redix_pid: redix_pid, channels: channels} = state, channel, %Subscription{} = subscription, method) do
    true = :ets.insert(channels, {channel, subscription})
    apply(Redix.PubSub, method, [redix_pid, include_ns(channel, state), self()])
  end
  defp subscribe_to_channel(_, _, _, _), do: :error

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
      {:error, _} -> Logger.error("No connection to Redis")
    end
  end
end
