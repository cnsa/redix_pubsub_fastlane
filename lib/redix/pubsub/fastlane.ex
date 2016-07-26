defmodule Redix.PubSub.Fastlane do
  alias Redix.PubSub.Fastlane.{Server, Supervisor}

  @moduledoc """
  Fastlane pattern based on Redix.PubSub interface.

  To use `Redix.PubSub.Fastlane`, simply add it to your Mix.config:

      config :redix_pubsub_fastlane,
        fastlane: Some.DefaultFastlane,
        host: "192.168.1.100"

  For full list of options: `Redix.PubSub.Fastlane.Supervisor`

  You will also need to add `:redix_pubsub_fastlane` to your deps:
      defp deps do
        [{:redix_pubsub_fastlane, "~> 0.1"}]
      end
  And also add `:phoenix_pubsub_redis` to your list of applications:
      def application do
        [mod: {MyApp, []},
         applications: [..., :redix_pubsub_fastlane]]
      end

  ## Usage

  Simply add it to your Supervisor stack:
      supervisor(Redix.PubSub.Fastlane.Supervisor, [MyApp.PubSub.Redis, [host: "localhost",
                                                                         port: 6397,
                                                                         pool_size: 5]]),
  Or run it by hands:
      {:ok, _} = Redix.PubSub.Fastlane.Supervisor.start_link(MyApp.PubSub.Redis)

  Subscription process:
      defmodule Some.Fastlane.Namespace do
        def fastlane(payload, options) do
          IO.inspect(payload)
          IO.inspect(options)
        end
      end

      {:ok, _pubsub} = Redix.PubSub.Fastlane.Supervisor.start_link(MyApp.PubSub.Redis)
      Redix.PubSub.Fastlane.subscribe(MyApp.PubSub.Redis, "my_channel", {Some.Fastlane.Namespace, [:some_id]})
      #=> :ok
  After a subscription, messages published to a channel are delivered `Some.Fastlane.Namespace.fastlane/2`,
  as it subscribed to that channel via `Redix.PubSub.Fastlane` or `Redix.PubSub`:
      Redix.PubSub.Fastlane.publish(MyApp.PubSub.Redis, "my_channel", "hello")
      #=> :ok
      #=> "hello"
      #=> [:some_id]

  If you haven't provided any fastlane, then you must provide a `PID` of the receiver process, as a fallback.
  The wrapper will not touch or store any part of incoming payload, just compare channel with cached one to find suitable fastlane.

  ## About

  Works as a simple wrapper over Redix.PubSub.

  Main goal is providing a fastlane path for the publisher with `{:redix_pubsub, _, :message, %{channel: channel, ...}}` events.

  Imagine: You have a task, that has few subtasks each with its own UUID & must await for published event, but also must know main task ID within every event.

  Ie:
      Redix.PubSub.Fastlane.subscribe(MyApp.PubSub.Redis, "channel1", {My.Fastlane, ["some_id"]})

  If you provide it, the fastlane handler is notified of a cached message instead of the normal subscriber.
  Fastlane handlers must implement `fastlane/2` callbacks which accepts similar format:

      def fastlane(%{channel: channel, payload: payload}, [:some_id])

  And returns a fastlaned format for the handler.
  """

  @doc """
  Subscribes the caller to the PubSub adapter's channel.
    * `server` - The Pid registered name of the server
    * `channel` - The channel to subscribe to, ie: `"users:123"`
    * `fastlane` - The tuple with fastlane module and it's arguments, ie: `{My.Fastlane, [:some_id]}`
  """
  @spec subscribe(atom, binary, term) :: :ok | {:error, term}
  def subscribe(server, channel, fastlane)
    when is_atom(server) and is_binary(channel) and is_tuple(fastlane) do
    Server.subscribe(server, channel, fastlane)
  end

  @doc """
  Subscribes the caller to the PubSub adapter's channel.
    * `server` - The Pid registered name of the server
    * `channel` - The channel to subscribe to, ie: `"users:123"`
    * `pid` - The pid of the caller.
  """
  @spec subscribe(atom, binary, pid) :: :ok | {:error, term}
  def subscribe(server, channel, pid)
    when is_atom(server) and is_binary(channel),
      do: Server.subscribe(server, channel, pid)

  @doc """
  Publish message on given channel.
    * `server` - The Pid or registered server name, for example: `MyApp.PubSub`
    * `channel` - The channel to publish to, ie: `"users:123"`
    * `message` - The payload of the publish
  """
  @spec publish(atom, binary, term) :: :ok | {:error, term}
  def publish(server, channel, message) when is_atom(server),
    do: Server.publish(server, channel, message)

  @doc """
  Stops the given PubSub Supervisor process.
  This function is asynchronous (*fire and forget*): it returns `:ok` as soon as
  it's called and performs the closing of the connection after that.
  ## Examples
      iex> {:ok, _} = Redix.PubSub.Fastlane.Supervisor.start_link(MyApp.PubSub.Redis)
      iex> Redix.PubSub.Fastlane.stop(MyApp.PubSub.Redis)
      :ok
  """
  @spec stop(atom) :: :ok
  def stop(server) do
    Supervisor.stop(server)
  end
end
