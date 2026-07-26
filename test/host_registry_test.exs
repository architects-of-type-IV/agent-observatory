defmodule HostRegistryTest do
  use ExUnit.Case, async: false

  alias HostRegistry.Host

  setup do
    Application.put_env(:host_registry, :capabilities, [:tmux, :spawn])
    Application.put_env(:host_registry, :notifier, HostRegistry.Notifier.ProcessMessage)
    Application.put_env(:host_registry, :notifier_target, self())

    start_supervised!(HostRegistry)

    on_exit(fn ->
      for key <- [:capabilities, :notifier, :notifier_target, :pg_scope, :pg_group] do
        Application.delete_env(:host_registry, key)
      end
    end)

    :ok
  end

  describe "startup" do
    test "the local node is known and connected" do
      assert [host] = HostRegistry.list_hosts()
      assert host.node == Node.self()
      assert host.status == :connected
    end

    test "the local node carries the configured capabilities" do
      assert [%Host{capabilities: [:tmux, :spawn]}] = HostRegistry.list_hosts()
    end

    test "joins its pg group" do
      assert Process.whereis(HostRegistry) in HostRegistry.members()
    end
  end

  describe "local_host/0" do
    test "describes this node" do
      host = HostRegistry.local_host()

      assert host.node == Node.self()
      assert host.status == :connected
      assert host.capabilities == [:tmux, :spawn]
      assert %DateTime{} = host.connected_at
    end
  end

  describe "available?/1" do
    test "is true for this node" do
      assert HostRegistry.available?(Node.self())
    end

    test "is false for a node that is not connected" do
      refute HostRegistry.available?(:ghost@nowhere)
    end

    test "stays false for a registered but unreachable node" do
      :ok = HostRegistry.register_host(:ghost@nowhere)

      assert HostRegistry.get_host(:ghost@nowhere)
      refute HostRegistry.available?(:ghost@nowhere)
    end
  end

  describe "register_host/2" do
    test "an unreachable node lands as :registered, not :connected" do
      assert :ok = HostRegistry.register_host(:"worker@box-2", %{region: "eu"})

      host = HostRegistry.get_host(:"worker@box-2")
      assert host.status == :registered
      assert host.metadata == %{region: "eu"}
      assert host.connected_at == nil
    end

    test "registering this node records it as connected" do
      :ok = HostRegistry.register_host(Node.self(), %{role: "primary"})

      host = HostRegistry.get_host(Node.self())
      assert host.status == :connected
      assert %DateTime{} = host.connected_at
    end

    test "metadata defaults to empty" do
      :ok = HostRegistry.register_host(:"worker@box-2")

      assert HostRegistry.get_host(:"worker@box-2").metadata == %{}
    end

    test "re-registering replaces the metadata" do
      :ok = HostRegistry.register_host(:"worker@box-2", %{region: "eu"})
      :ok = HostRegistry.register_host(:"worker@box-2", %{region: "us"})

      assert HostRegistry.get_host(:"worker@box-2").metadata == %{region: "us"}
    end

    test "notifies with the full host list" do
      :ok = HostRegistry.register_host(:"worker@box-2")

      assert_receive {:host_registry, :hosts_changed, hosts}
      assert length(hosts) == 2
    end
  end

  describe "get_host/1" do
    test "returns nil for an unknown node" do
      assert HostRegistry.get_host(:nobody@nowhere) == nil
    end
  end

  describe "remove_host/1" do
    test "forgets the host" do
      :ok = HostRegistry.register_host(:"worker@box-2")

      assert :ok = HostRegistry.remove_host(:"worker@box-2")
      assert HostRegistry.get_host(:"worker@box-2") == nil
    end

    test "notifies" do
      :ok = HostRegistry.register_host(:"worker@box-2")
      assert_receive {:host_registry, :hosts_changed, _}

      :ok = HostRegistry.remove_host(:"worker@box-2")
      assert_receive {:host_registry, :hosts_changed, hosts}
      assert length(hosts) == 1
    end

    test "removing an unknown node is a no-op" do
      assert :ok = HostRegistry.remove_host(:nobody@nowhere)
    end
  end

  describe "list_connected/0" do
    test "excludes registered-but-unreachable hosts" do
      :ok = HostRegistry.register_host(:"worker@box-2")

      assert [host] = HostRegistry.list_connected()
      assert host.node == Node.self()
    end
  end

  describe "node monitoring" do
    test "a nodeup adds the host as connected" do
      send(HostRegistry, {:nodeup, :"worker@box-3", []})

      assert_receive {:host_registry, :hosts_changed, _}
      host = HostRegistry.get_host(:"worker@box-3")
      assert host.status == :connected
      assert %DateTime{} = host.connected_at
    end

    test "a nodeup for a registered host keeps its metadata" do
      :ok = HostRegistry.register_host(:"worker@box-3", %{region: "eu"})
      send(HostRegistry, {:nodeup, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}
      assert_receive {:host_registry, :hosts_changed, _}

      host = HostRegistry.get_host(:"worker@box-3")
      assert host.status == :connected
      assert host.metadata == %{region: "eu"}
    end

    test "a nodedown marks the host disconnected rather than deleting it" do
      send(HostRegistry, {:nodeup, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}

      send(HostRegistry, {:nodedown, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}

      host = HostRegistry.get_host(:"worker@box-3")
      assert host.status == :disconnected
      assert host.node == :"worker@box-3"
    end

    test "a nodedown for an unknown node does not insert a bogus entry" do
      send(HostRegistry, {:nodedown, :"never-seen@nowhere", []})

      # No notification, because nothing changed.
      refute_receive {:host_registry, :hosts_changed, _}, 100

      assert HostRegistry.get_host(:"never-seen@nowhere") == nil
      assert [%Host{}] = HostRegistry.list_hosts()
      assert Enum.all?(HostRegistry.list_hosts(), &match?(%Host{}, &1))
    end

    test "an unrelated message is ignored" do
      send(HostRegistry, :something_else)

      assert Process.alive?(Process.whereis(HostRegistry))
      assert [%Host{}] = HostRegistry.list_hosts()
    end

    test "a node that comes back flips to connected again" do
      send(HostRegistry, {:nodeup, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}
      send(HostRegistry, {:nodedown, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}
      send(HostRegistry, {:nodeup, :"worker@box-3", []})
      assert_receive {:host_registry, :hosts_changed, _}

      assert HostRegistry.get_host(:"worker@box-3").status == :connected
    end
  end

  describe "notifier" do
    test "the default no-op does not send anything" do
      Application.put_env(:host_registry, :notifier, HostRegistry.Notifier.Noop)

      :ok = HostRegistry.register_host(:"worker@box-2")
      refute_receive {:host_registry, :hosts_changed, _}, 100
    end

    test "ProcessMessage with no target is not an error" do
      Application.delete_env(:host_registry, :notifier_target)

      assert :ok = HostRegistry.register_host(:"worker@box-2")
      refute_receive {:host_registry, :hosts_changed, _}, 100
    end
  end
end
