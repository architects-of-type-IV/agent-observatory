defmodule MemoryStore.NotifierTest do
  use MemoryStore.StoreCase

  describe "with the default no-op notifier" do
    test "mutations succeed and nothing is sent" do
      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact")

      refute_receive {:memory_store, _, _, _}, 50
    end
  end

  describe "with the ProcessMessage notifier" do
    setup do
      put_config(:notifier, MemoryStore.Notifier.ProcessMessage)
      put_config(:notifier_target, self())
      :ok
    end

    test "create_agent notifies" do
      {:ok, _} = MemoryStore.create_agent("scout")

      assert_receive {:memory_store, :agent_created, "scout", %{agent_name: "scout"}}
    end

    test "archival_memory_insert notifies with the passage id" do
      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, passage} = MemoryStore.archival_memory_insert("scout", "fact")

      assert_receive {:memory_store, :archival_insert, "scout", %{passage_id: id}}
      assert id == passage.id
    end

    test "a rejected create does not notify" do
      {:ok, _} = MemoryStore.create_agent("scout")
      assert_receive {:memory_store, :agent_created, "scout", _}

      assert {:error, :already_exists} = MemoryStore.create_agent("scout")
      refute_receive {:memory_store, :agent_created, "scout", _}, 50
    end

    test "block edits do not notify" do
      {:ok, _} = MemoryStore.create_agent("scout", [%{label: "persona", value: "v"}])
      assert_receive {:memory_store, :agent_created, _, _}

      {:ok, _} = MemoryStore.memory_rethink("scout", "persona", "changed")
      refute_receive {:memory_store, _, _, _}, 50
    end

    test "no target configured is not an error" do
      Application.delete_env(:memory_store, :notifier_target)

      assert {:ok, _} = MemoryStore.create_agent("scout")
      refute_receive {:memory_store, _, _, _}, 50
    end
  end

  describe "with a custom notifier" do
    defmodule Collector do
      @moduledoc false
      @behaviour MemoryStore.Notifier

      @impl true
      def notify(event, agent_name, payload) do
        send(:notifier_collector, {:collected, event, agent_name, payload})
      end
    end

    test "the configured module receives every event" do
      Process.register(self(), :notifier_collector)
      put_config(:notifier, Collector)

      {:ok, _} = MemoryStore.create_agent("scout")
      {:ok, _} = MemoryStore.archival_memory_insert("scout", "fact")

      assert_receive {:collected, :agent_created, "scout", _}
      assert_receive {:collected, :archival_insert, "scout", _}
    end
  end
end
