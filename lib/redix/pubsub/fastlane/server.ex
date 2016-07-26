defmodule Redix.PubSub.Fastlane.Server do
  @moduledoc false

  use GenServer
  require Logger

  @redix_opts [:host, :port, :password, :database]

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
    channels = :ets.new(opts[:server_name], [:set, :named_table, {:read_concurrency, true}])

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
  def subscribe(pubsub_server, channel, fastlane), do: GenServer.call(pubsub_server, {:subscribe, channel, fastlane})

  @doc false
  def publish(pubsub_server, channel, message), do: GenServer.call(pubsub_server, {:publish, channel, message})

  @doc false
  def drop(pubsub_server, channel), do: GenServer.cast(pubsub_server, {:drop, channel})

  def handle_call({:publish, channel, message}, _from, state) do
    {:reply, _publish(channel, message, state.pool_name), state}
  end

  def handle_call(:lookup, _from, state) do
    {:reply, self(), state}
  end

  def handle_call({:find, channel}, _from, %{channels: channels} = state) do
    result = _find(channels, channel)

    {:reply, result, state}
  end

  def handle_call({:subscribe, channel, fastlane}, _from, %{channels: _, redix_pid: _} = state) do
    subscription = _subscribe(channel, fastlane, state)
    {:reply, subscription, state}
  end

  def handle_cast(:stop, _state) do
    {:stop, :normal}
  end

  def handle_cast({:drop, channel}, %{channels: channels} = state) do
    true = :ets.delete(channels, channel)

    {:noreply, state}
  end

  def handle_info({:redix_pubsub, redix_pid, :subscribed, _}, %{redix_pid: redix_pid} = state) do
    {:noreply, state}
  end

  def handle_info({:redix_pubsub, redix_pid, :message, %{payload: payload, channel: channel}}, %{channels: channels, redix_pid: redix_pid} = state) do
    case _find(channels, channel) do
      {:ok, %{subscription: subscription}} ->
        module = subscription.parent || state.fastlane
        module.fastlane(payload, subscription.options)
        drop(state.server_name, channel)
      _ -> nil
    end

    {:noreply, state}
  end

  @doc """
  Connection establishment and shutdown loop
  On init, an initial conection to redis is attempted when starting `:redix`
  """
  def terminate(_reason, _state) do
    :ok
  end

  defp _find(channels, channel) do
    case :ets.lookup(channels, channel) do
      [{^channel, subscription}] -> {:ok, %{ id: channel, subscription: subscription}}
      [] -> :error
    end
  end

  defp _publish(channel, {serializer, message}, server_name) when is_function(serializer, 1) do
    _publish_message(channel, serializer.(message), server_name)
  end
  defp _publish(channel, message, server_name) do
    _publish_message(channel, message, server_name)
  end

  defp _publish_message(channel, message, server_name) do
    :poolboy.transaction server_name, fn(redix_pid) ->
      case Redix.command(redix_pid, ["PUBLISH", channel, message]) do
        {:ok, _} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp _subscribe(channel, {parent, options}, state) do
    subscription = %Subscription{parent: parent, options: options, channel: channel}
    subscribe_to_channel(state, channel, subscription)
    :ok
  end
  defp _subscribe(channel, pid, state) do
    subscribe_to_channel(state, channel, pid)
    :ok
  end

  defp subscribe_to_channel(%{connected: true, redix_pid: redix_pid, channels: channels}, channel, %Subscription{} = subscription) do
    true = :ets.insert(channels, {channel, subscription})
    :ok  = Redix.PubSub.subscribe(redix_pid, channel, self())
  end
  defp subscribe_to_channel(%{connected: true, redix_pid: redix_pid}, channel, pid) do
    :ok  = Redix.PubSub.subscribe(redix_pid, channel, pid)
  end
  defp subscribe_to_channel(_, _, _), do: :error

  defp establish_conn(state) do
    redis_opts = Keyword.take(state.opts, @redix_opts)
    case Redix.PubSub.start_link(redis_opts) do
      {:ok, redix_pid} -> %{state | redix_pid: redix_pid, connected: true}
      {:error, _} -> Logger.error("No connection to Redis")
    end
  end
end
