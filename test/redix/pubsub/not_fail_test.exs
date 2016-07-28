defmodule Redix.PubSub.NotFailTest do
  use ExSpec, async: false

  alias Redix.PubSub

  @publish_timeout 30

  setup do
    {:ok, conn} = PubSub.start_link()
    on_exit(fn ->
      PubSub.stop(conn)
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
