defmodule Redix.PubSub.NotFailTest do
  use ExSpec, async: false

  alias Redix.PubSub

  setup do
    {:ok, conn} = PubSub.start_link([], [name: :redix_pubsub])
    on_exit(fn ->
      if Process.whereis(:redix_pubsub) do
        PubSub.stop(conn)
      end
    end)
    {:ok, %{conn: conn}}
  end

  it "Not fails with second unsubscribe", %{conn: conn} do
    assert :ok = PubSub.subscribe(conn, "ccc", self())
    assert :ok = PubSub.psubscribe(conn, "bbb", self())
    assert :ok = PubSub.punsubscribe(conn, "aaa", self())
    assert :ok = PubSub.punsubscribe(conn, "aaa", self())
    assert :ok = PubSub.unsubscribe(conn, "ddd", self())
    assert :ok = PubSub.unsubscribe(conn, "ddd", self())
    assert :ok = PubSub.unsubscribe(conn, "ccc", self())

    assert_receive {:redix_pubsub, ^conn, :punsubscribed, _}
    assert_receive {:redix_pubsub, ^conn, :punsubscribed, _}
    assert_receive {:redix_pubsub, ^conn, :unsubscribed, _}
    assert_receive {:redix_pubsub, ^conn, :unsubscribed, _}
    assert_receive {:redix_pubsub, ^conn, :unsubscribed, _}
  end
end
