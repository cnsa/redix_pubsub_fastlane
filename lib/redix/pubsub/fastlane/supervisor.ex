defmodule Redix.PubSub.Fastlane.Supervisor do
  use Supervisor

  @moduledoc """
  Fastlane Supervisor process.
  To use simply add it to your Application supervisors:
      supervisor(Redix.PubSub.Fastlane.Supervisor, [MyApp.PubSub.Redis, [host: "127.0.0.1",
                                                                         port: 6379,
                                                                         pool_size: 5]]),
  Or start by hands:
      {:ok, _} = Redix.PubSub.Fastlane.Supervisor.start_link(MyApp.PubSub.Redis)

  ## Options
    * `:name` - The required name to register the PubSub processes, ie: `MyApp.PubSub.Redis`
    * `:host` - The redis-server host IP, defaults `"127.0.0.1"`
    * `:port` - The redis-server port, defaults `6379`
    * `:database` - The redis-server database id, defaults `""`
    * `:password` - The redis-server password, defaults `""`
    * `:pool_size` - The size of hte redis connection pool. Defaults `5`
    * `:fastlane` - The default fastlane module. Defaults `nil`
  """

  @pool_size 5
  @defaults [host: "127.0.0.1", port: 6379]
  @config_key :redix_pubsub_fastlane

  @spec start_link(binary|atom, Keyword.t) :: GenServer.on_start
  def start_link(name, opts \\ []) do
    Supervisor.start_link(__MODULE__, [name, opts], name: supervisor_module(name))
  end

  @doc false
  def stop(name), do: Supervisor.stop(supervisor_module(name))

  @doc false
  def init([server_name, opts]) do
    opts = Keyword.merge(@defaults, config) |> Keyword.merge(opts)
    redis_opts = Keyword.take(opts, [:host, :port, :password, :database])

    pool_name   = Module.concat(server_name, Pool)
    server_opts = Keyword.merge(opts, pool_name: pool_name,
                                      server_name: server_name,
                                      fastlane: opts[:fastlane],
                                      namespace: server_name)

    pool_opts = [
      name: {:local, pool_name},
      worker_module: Redix,
      size: opts[:pool_size] || @pool_size,
      max_overflow: 0
    ]

    children = [
      worker(Redix.PubSub.Fastlane.Server, [server_opts]),
      :poolboy.child_spec(pool_name, pool_opts, redis_opts),
    ]

    supervise children, strategy: :rest_for_one
  end

  defp supervisor_module(name), do: Module.concat(name, Supervisor)

  defp config do
    Application.get_all_env(@config_key)
    |> Keyword.take([:host, :port, :password, :database, :password, :fastlane])
  end
end
