# Redix.PubSub.Fastlane

> Fastlane pattern based on Redix.PubSub interface for Elixir

[![Build Status](https://travis-ci.org/cnsa/redix_pubsub_fastlane.svg?branch=master)](https://travis-ci.org/cnsa/redix_pubsub_fastlane)
[![Coverage Status](https://coveralls.io/repos/github/cnsa/redix_pubsub_fastlane/badge.svg?branch=master)](https://coveralls.io/github/cnsa/redix_pubsub_fastlane?branch=master)
[![Hex.pm](https://img.shields.io/hexpm/v/redix_pubsub_fastlane.svg?maxAge=2592000)](https://hex.pm/packages/redix_pubsub_fastlane)
[![Deps Status](https://beta.hexfaktor.org/badge/prod/github/merqlove/redix_pubsub_fastlane.svg)](https://beta.hexfaktor.org/github/merqlove/redix_pubsub_fastlane)

See the [docs](https://hexdocs.pm/redix_pubsub_fastlane/) for more information.

TL;DR [Example Phoenix app](https://github.com/merqlove/elixir-docker-compose)

## About

Works as a simple wrapper over [Redix.PubSub](https://hexdocs.pm/redix_pubsub/).

Main goal is providing a fastlane path for published events.

Imagine: You have a `Main` task, that depends on few subtasks, each with its own UUID & in they await for published event, but also must know  the `Main` task ID within every event.

Ie:

```elixir
Redix.PubSub.Fastlane.subscribe(MyApp.PubSub.Redis, "channel1", {pid, My.Fastlane, ["some_id"]})
```

## Installation

`redix_pubsub_fastlane` can be installed as:

1. Add `redix_pubsub_fastlane` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:redix_pubsub_fastlane, "~> 0.3.1"}]
  end
  ```

2. Ensure `redix_pubsub_fastlane` is started before your application:

  ```elixir
  def application do
    [applications: [:redix_pubsub_fastlane]]
  end
```

3. Also you can simply add it to your Mix.config:

  ```elixir
  config :redix_pubsub_fastlane, MyApp.PubSub.Redis,
    fastlane: My.Fastlane,
    host: "192.168.1.100"

  ```

## Usage

Simply add it to your Supervisor stack:

```elixir
supervisor(Redix.PubSub.Fastlane, [MyApp.PubSub.Redis, [host: "localhost",
                                                        port: 6397,
                                                        pool_size: 5]])
```

Or run it by hands:

```elixir
{:ok, pubsub_server} = Redix.PubSub.Fastlane.start_link(MyApp.PubSub.Redis)
```

### Config Options

Option       | Description                                                            | Default        |
:----------- | :--------------------------------------------------------------------- | :------------- |
`:name`      | The required name to register the PubSub processes, ie: `MyApp.PubSub` |                |
`:fastlane`  | The name of base fastlane module, ie: `My.Fastlane`                    | none           |
`:decoder`   | The decoder method for payloads, ie: `&Poison.decode!/1`               | none           |
`:database`  | The redis-server database                                              | `""`           |
`:host`      | The redis-server host IP                                               | `"127.0.0.1"`  |
`:port`      | The redis-server port                                                  | `6379`         |
`:password`  | The redis-server password                                              | `""`           |


Inspired by:

- [phoenix_pubsub_redis](https://github.com/phoenixframework/phoenix_pubsub_redis)

## License

[MIT](LICENSE.txt)
