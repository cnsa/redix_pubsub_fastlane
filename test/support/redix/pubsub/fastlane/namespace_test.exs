defmodule Redix.PubSub.Fastlane.NamespaceTest do
  use GenServer

  def start_link(opts) when is_list(opts) do
    GenServer.start_link(__MODULE__, opts, name: FastlaneTestNamespace)
  end

  def init(opts), do: {:ok, opts}

  def stop(pid) do
    GenServer.cast(pid, :stop)
  end

  def fastlane(subscribers, message) do
    subscribers
    |> Enum.each(fn
      {_from, {pid, _parent, options}} ->
         __MODULE__.fastlane(pid, message, options)
      _ -> :noop
    end)
  end

  def fastlane(pid, payload, options) do
    GenServer.cast(FastlaneTestNamespace, {:fastlane, pid, payload, options})
    :ok
  end

  def handle_cast({:fastlane, pid, payload, options}, state) do
    send(state[:pid], {:fastlane, pid, payload, options})
    {:noreply, state}
  end

  def handle_cast(:stop, state) do
    {:stop, :normal, state}
  end

  def terminate(_, _), do: :ok
end
