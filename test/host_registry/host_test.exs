defmodule HostRegistry.HostTest do
  use ExUnit.Case, async: true

  alias HostRegistry.Host

  doctest HostRegistry.Host

  describe "hostname/1" do
    test "takes the part after the @" do
      assert Host.hostname(:"worker@box-1") == "box-1"
      assert Host.hostname(:"app@10.0.0.5") == "10.0.0.5"
    end

    test "handles a fully qualified name" do
      assert Host.hostname(:"app@box.internal.example.com") == "box.internal.example.com"
    end

    test "returns the name itself when there is no @" do
      assert Host.hostname(:standalone) == "standalone"
    end

    test "handles the default unclustered node name" do
      assert Host.hostname(:nonode@nohost) == "nohost"
    end
  end

  describe "new/3" do
    test "stamps connected_at only for a connected host" do
      assert %Host{connected_at: %DateTime{}} = Host.new(:a@b, :connected)
      assert %Host{connected_at: nil} = Host.new(:a@b, :registered)
      assert %Host{connected_at: nil} = Host.new(:a@b, :disconnected)
    end

    test "derives the hostname from the node" do
      assert Host.new(:"worker@box-1", :connected).hostname == "box-1"
    end

    test "defaults capabilities and metadata to empty" do
      host = Host.new(:a@b, :connected)

      assert host.capabilities == []
      assert host.metadata == %{}
    end

    test "carries capabilities and metadata through" do
      host = Host.new(:a@b, :connected, capabilities: [:tmux], metadata: %{region: "eu"})

      assert host.capabilities == [:tmux]
      assert host.metadata == %{region: "eu"}
    end
  end
end
