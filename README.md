# Redix.PubSub.Fastlane

> Fastlane pattern based on Redix.PubSub interface for Elixir

[![Build Status](https://travis-ci.org/merqlove/redix_pubsub_fastlane.svg?branch=master)](https://travis-ci.org/merqlove/redix_pubsub_fastlane)
[![Coverage Status](https://coveralls.io/repos/github/merqlove/redix_pubsub_fastlane/badge.svg?branch=master)](https://coveralls.io/github/merqlove/redix_pubsub_fastlane?branch=master)
[![Deps Status](https://beta.hexfaktor.org/badge/all/github/merqlove/redix_pubsub_fastlane.svg)](https://beta.hexfaktor.org/github/merqlove/redix_pubsub_fastlane)

See the [docs](https://hexdocs.pm/redix_pubsub_fastlane/) for more information.

## About

Works as a simple wrapper over [Redix.PubSub](https://hexdocs.pm/redix_pubsub/).

Main goal is providing a fastlane path for published events.

Imagine: You have a `Main` task, that depends on few subtasks, each with its own UUID & in they await for published event, but also must know  the `Main` task ID within every event.

Ie:

```elixir
Redix.PubSub.Fastlane.subscribe(MyApp.PubSub.Redis, "channel1", {My.Fastlane, ["some_id"]})
```

## Installation

`redix_pubsub_fastlane` can be installed as:

1. Add `redix_pubsub_fastlane` to your list of dependencies in `mix.exs`:

  ```elixir
  def deps do
    [{:redix_pubsub_fastlane, "~> 0.1.0"}]
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
  config :redix_pubsub_fastlane,
    fastlane: Some.DefaultFastlane,
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
`:fastlane`  | The name of default fastlane module, ie: `MyApp.Fastlane`              | `nil`          |
`:database`  | The redis-server database                                              | `""`           |
`:host`      | The redis-server host IP                                               | `"127.0.0.1"`  |
`:port`      | The redis-server port                                                  | `6379`         |
`:password`  | The redis-server password                                              | `""`           |


Inspired by:

- [phoenix_pubsub_redis](https://github.com/phoenixframework/phoenix_pubsub_redis)

## License

Copyright (c) 2016 Alexander Merkulov

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
