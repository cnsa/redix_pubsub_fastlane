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
    * `:decoder` - The decoder for your incoming payloads. Defaults `nil`
  """

  @pool_size 5
  @timeout 5_000
  @defaults [host: "127.0.0.1", port: 6379]
  @config_key :redix_pubsub_fastlane
  @config_keys [:host, :port, :password, :database, :password, :fastlane, :decoder]

  @spec start_link(binary|atom, Keyword.t) :: GenServer.on_start
  def start_link(name, opts \\ []) do
    Supervisor.start_link(__MODULE__, [name, opts], name: supervisor_module(name))
  end

  @doc false
  def stop(name) do
    pid =
      supervisor_module(name)
      |> Process.whereis

    ref = Process.monitor(pid)

    pid
    |> stop_process(ref)
  end

  @doc false
  def init([server_name, opts]) do
    opts = Keyword.merge(@defaults, config(server_name)) |> Keyword.merge(opts)
    redis_opts = Keyword.take(opts, [:host, :port, :password, :database])

    pool_name   = Module.concat(server_name, Pool)
    decoder     = opts[:decoder] || fn(payload) -> payload end
    server_opts = Keyword.merge(opts, pool_name: pool_name,
                                      server_name: server_name,
                                      decoder: decoder,
                                      fastlane: opts[:fastlane],
                                      namespace: cleanup_namespace(server_name))

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

  defp stop_process(pid, ref) when is_pid(pid) do
    Process.exit(pid, :normal)
    receive do
      {:DOWN, ^ref, _, _, _} -> :ok
    after
      @timeout -> exit(:timeout)
    end
    :ok
  end
  defp stop_process(_, _), do: :error

  defp cleanup_namespace(name) do
    case "#{name}" do
      "Elixir." <> suffix -> suffix
      _                   -> name
    end
  end

  defp config(name) do
    case Application.get_env(@config_key, name) do
      nil    -> []
      config -> Keyword.take(config, @config_keys)
    end
  end
end
