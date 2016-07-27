defmodule Redix.PubSub.FastlaneTest do
  use ExSpec, async: false

  alias Redix.PubSub.Fastlane.NamespaceTest, as: FastlaneNamespace
  alias Redix.PubSub.{Fastlane, Fastlane.Server, Fastlane.Server.Subscription}

  @publish_timeout 30

  setup do
    {:ok, _} = FastlaneNamespace.start_link(pid: self())
    on_exit(fn ->
      FastlaneNamespace.stop
    end)
    :ok
  end

  describe "default config" do
    setup do
      {:ok, _} = Fastlane.start_link(MyApp.PubSub.Redis)
      on_exit(fn ->
        Fastlane.stop(MyApp.PubSub.Redis)
      end)
      {:ok, %{conn: MyApp.PubSub.Redis}}
    end

    context "subscribe/unsubscribe" do
      it "standard flow", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.subscribe(ps, "foo", {FastlaneNamespace, [:some_id]})
        assert :ok = Fastlane.subscribe(ps, "bar", {FastlaneNamespace, [:some_second_id]})

        assert match? {:ok, %{id: "foo",
                              subscription: %Subscription{channel: "foo",
                                                          options: [:some_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "foo")
        assert match? {:ok, %{id: "bar",
                              subscription: %Subscription{channel: "bar",
                                                          options: [:some_second_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "bar")
        assert match? :error, Server.find(ps, "tar")

        # Next we unsubscribe

        assert :ok = Fastlane.unsubscribe(ps, "foo")

        assert match? :error, Server.find(ps, "foo")
        assert match? {:ok, %{id: "bar",
                              subscription: %Subscription{channel: "bar",
                                                          options: [:some_second_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "bar")

        assert :ok = Fastlane.unsubscribe(ps, "bar")
        assert match? :error, Server.find(ps, "bar")
      end

      it "pattern flow", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.psubscribe(ps, "foo*", {FastlaneNamespace, [:some_id]})
        assert :ok = Fastlane.psubscribe(ps, "bar*", {FastlaneNamespace, [:some_second_id]})

        assert match? {:ok, %{id: "foo*",
                              subscription: %Subscription{channel: "foo*",
                                                          options: [:some_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "foo*")
        assert match? {:ok, %{id: "bar*",
                              subscription: %Subscription{channel: "bar*",
                                                          options: [:some_second_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "bar*")
        assert match? :error, Server.find(ps, "tar*")

        # Next we unsubscribe

        assert :ok = Fastlane.punsubscribe(ps, "foo*")

        assert match? :error, Server.find(ps, "foo*")
        assert match? {:ok, %{id: "bar*",
                              subscription: %Subscription{channel: "bar*",
                                                          options: [:some_second_id],
                                                          parent: FastlaneNamespace}}}, Server.find(ps, "bar*")

        assert :ok = Fastlane.punsubscribe(ps, "bar*")
        assert match? :error, Server.find(ps, "bar*")
      end
    end

    context "publish" do
      it "standard test", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.subscribe(ps, "foo", {FastlaneNamespace, [:some_id]})
        assert :ok = Fastlane.subscribe(ps, "bar", {FastlaneNamespace, [:some_second_id]})

        assert match? {:ok, _}, Server.find(ps, "foo")
        assert match? {:ok, _}, Server.find(ps, "bar")

        # Then, we test messages are routed correctly.
        publish(ps, "foo", "hello")
        assert_receive {:fastlane, %{channel: "foo", payload: "hello"}, [:some_id]}
        publish(ps, "bar", "world")
        assert_receive {:fastlane, %{channel: "bar", payload: "world"}, [:some_second_id]}
      end

      it "pattern test", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.psubscribe(ps, "foo*", {FastlaneNamespace, [:some_id]})
        assert :ok = Fastlane.psubscribe(ps, "bar*", {FastlaneNamespace, [:some_second_id]})

        # Then, we test messages are routed correctly.
        publish(ps, "foo_1", "hello")
        publish(ps, "foo_2", "hello1")
        publish(ps, "foo_3", "hello2")
        assert_receive {:fastlane, %{channel: "foo_1", pattern: "foo*", payload: "hello"}, [:some_id]}
        assert_receive {:fastlane, %{channel: "foo_2", pattern: "foo*", payload: "hello1"}, [:some_id]}
        assert_receive {:fastlane, %{channel: "foo_3", pattern: "foo*", payload: "hello2"}, [:some_id]}
        publish(ps, "bar_1", "world")
        publish(ps, "bar_2", "world1")
        publish(ps, "bar_3", "world2")
        assert_receive {:fastlane, %{channel: "bar_1", pattern: "bar*", payload: "world"}, [:some_second_id]}
        assert_receive {:fastlane, %{channel: "bar_2", pattern: "bar*", payload: "world1"}, [:some_second_id]}
        assert_receive {:fastlane, %{channel: "bar_3", pattern: "bar*", payload: "world2"}, [:some_second_id]}

        assert :ok = Fastlane.punsubscribe(ps, "bar*")
        publish(ps, "bar_1", "world")
        refute_receive {:fastlane, %{channel: "bar_1", pattern: "bar*", payload: "world"}, [:some_second_id]}
      end

      it "serializer test", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.subscribe(ps, "foo", {FastlaneNamespace, [:some_id]})
        assert :ok = Fastlane.subscribe(ps, "bar", {FastlaneNamespace, [:some_second_id]})

        # Then, we test messages are routed correctly.
        publish(ps, "foo", {&Poison.encode!/1, %{a: "hello1"}})
        publish(ps, "bar", {&Poison.encode!/1, %{b: 1}})
        assert_receive {:fastlane, %{channel: "foo", payload: "{\"a\":\"hello1\"}"}, [:some_id]}
        assert_receive {:fastlane, %{channel: "bar", payload: "{\"b\":1}"}, [:some_second_id]}

        assert :ok = Fastlane.unsubscribe(ps, "bar")
        publish(ps, "bar", {&Poison.encode!/1, %{b: 1}})
        refute_receive {:fastlane, %{channel: "bar", payload: "{\"b\":1}"}, [:some_second_id]}
      end
    end
  end

  describe "with custom elements" do
    setup do
      {:ok, _} = Fastlane.start_link(:some_app_name, [pool_size: 10, fastlane: FastlaneNamespace])
      on_exit(fn ->
        Fastlane.stop(:some_app_name)
      end)
      {:ok, %{conn: :some_app_name}}
    end

    context "settings" do
      it "standard test", %{conn: ps} do
        # First, we subscribe.
        assert :ok = Fastlane.subscribe(ps, "foo", {nil, [:some_id]})
        assert :ok = Fastlane.subscribe(ps, "bar", {FastlaneNamespace, [:some_second_id]})

        assert match? {:ok, _}, Server.find(ps, "foo")
        assert match? {:ok, _}, Server.find(ps, "bar")

        # Then, we test messages are routed correctly.
        publish(ps, "foo", "hello")
        assert_receive {:fastlane, %{channel: "foo", payload: "hello"}, [:some_id]}
        publish(ps, "bar", "world")
        assert_receive {:fastlane, %{channel: "bar", payload: "world"}, [:some_second_id]}
      end
    end
  end

  defp publish(pid, channel, message, timeout \\ @publish_timeout) do
    {:ok, _} = :timer.apply_after(timeout, Fastlane, :publish, [pid, channel, message])
  end
end
