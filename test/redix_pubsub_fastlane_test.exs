defmodule Some.Fastlane.Namespace do
  def fastlane(payload, options) do
    IO.inspect(payload)
    IO.inspect(options)
  end
end

defmodule Redix.Pubsub.FastlaneTest do
  use ExUnit.Case
  import Redix.TestHelpers
  alias Redix.PubSub.Fastlane

  setup do
    {:ok, _} = Fastlane.start_link(MyApp.PubSub.Redis)
    on_exit(fn ->
      Fastlane.stop(MyApp.PubSub.Redis)
    end)
    {:ok, %{conn: MyApp.PubSub.Redis}}
  end

  test "the truth" do
    assert 1 + 1 == 2
  end
end
