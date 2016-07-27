defmodule RedixPubsubFastlane.Mixfile do
  use Mix.Project

  @project_url "https://github.com/merqlove/redix_pubsub_fastlane"
  @version "0.1.0"

  def project do
    [app: :redix_pubsub_fastlane,
     version: @version,
     elixir: "~> 1.0",
     elixirc_paths: elixirc_paths(Mix.env),
     build_embedded: Mix.env == :prod,
     start_permanent: Mix.env == :prod,
     deps: deps,
     source_url: @project_url,
     homepage_url: @project_url,
     description: "Fastlane pattern based on Redix.PubSub interface for Elixir",
     package: package,
     test_coverage: [tool: ExCoveralls],
     preferred_cli_env: cli_env_for(:test, [
       "coveralls", "coveralls.detail", "coveralls.html", "coveralls.post",
     ]),
     docs: docs]
  end

  def application do
    [applications: [:logger, :poolboy, :redix, :redix_pubsub]]
  end

  defp elixirc_paths(:test), do: elixirc_paths ++ ["test/support"]
  defp elixirc_paths(_),     do: elixirc_paths
  defp elixirc_paths,        do: ["lib"]

  defp deps do
    [
      {:redix, "~> 0.4.0"},
      {:redix_pubsub, "~> 0.1"},
      {:poolboy, "~> 1.5.1 or ~> 1.6"},
      {:poison, "~> 2.0", only: :test},
      {:ex_doc, "~> 0.11.1", only: :docs},
      {:earmark, ">= 0.0.0", only: :docs},
      {:ex_spec, "~> 2.0.0", only: :test},
      {:excoveralls, "~> 0.5", only: :test},
    ]
  end

  defp cli_env_for(env, tasks) do
    Enum.reduce(tasks, [], fn(key, acc) -> Keyword.put(acc, :"#{key}", env) end)
  end

  defp package do
    [
      name: "Redix.Pubsub.Fastlane",
      maintainers: ["Alexander Merkulov"],
      licenses: ["MIT"],
      links: %{
        "GitHub" => @project_url
      }
    ]
  end

  defp docs do
    [
       main: "Redix.PubSub.Fastlane",
       source_ref: "v#{@version}",
       source_url: @project_url
    ]
  end
end
