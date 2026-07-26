defmodule TmuxChannel.ConfigTest do
  use ExUnit.Case, async: false

  alias TmuxChannel.Config
  alias TmuxChannel.ServerSelector

  setup do
    ServerSelector.reset_cache()

    on_exit(fn ->
      for key <- [:socket_path, :server_name, :buffer_prefix, :server_cache_ttl_ms] do
        Application.delete_env(:tmux_channel, key)
      end

      ServerSelector.reset_cache()
    end)
  end

  test "defaults are usable without any configuration" do
    assert Config.server_name() == "tmux_channel"
    assert Config.buffer_prefix() == "tmux-channel"
    assert Config.socket_path() =~ "/.tmux_channel/tmux.sock"
  end

  test "socket_path expands ~" do
    Application.put_env(:tmux_channel, :socket_path, "~/somewhere/x.sock")
    refute String.starts_with?(Config.socket_path(), "~")
    assert String.ends_with?(Config.socket_path(), "/somewhere/x.sock")
  end

  describe "server_arg_sets/0" do
    test "omits the socket entry when the socket file does not exist" do
      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")
      Application.put_env(:tmux_channel, :server_name, "srv")

      assert Config.server_arg_sets() == [["-L", "srv"], []]
    end

    test "puts the socket first when it exists" do
      socket = Path.join(System.tmp_dir!(), "tc_#{:erlang.unique_integer([:positive])}.sock")
      File.write!(socket, "")
      on_exit(fn -> File.rm(socket) end)

      Application.put_env(:tmux_channel, :socket_path, socket)
      Application.put_env(:tmux_channel, :server_name, "srv")

      assert Config.server_arg_sets() == [["-S", socket], ["-L", "srv"], []]
    end

    test "always ends with the default server so tmux is reachable unconfigured" do
      assert List.last(Config.server_arg_sets()) == []
    end
  end

  describe "ServerSelector caching" do
    test "caches within the TTL and rebuilds after reset" do
      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")
      Application.put_env(:tmux_channel, :server_name, "first")
      assert ServerSelector.server_arg_sets() == [["-L", "first"], []]

      Application.put_env(:tmux_channel, :server_name, "second")
      assert ServerSelector.server_arg_sets() == [["-L", "first"], []]

      ServerSelector.reset_cache()
      assert ServerSelector.server_arg_sets() == [["-L", "second"], []]
    end

    test "a zero TTL disables caching" do
      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")
      Application.put_env(:tmux_channel, :server_cache_ttl_ms, 0)
      Application.put_env(:tmux_channel, :server_name, "a")
      assert ServerSelector.server_arg_sets() == [["-L", "a"], []]

      Application.put_env(:tmux_channel, :server_name, "b")
      assert ServerSelector.server_arg_sets() == [["-L", "b"], []]
    end

    test "the cache is per-process" do
      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")
      Application.put_env(:tmux_channel, :server_name, "outer")
      assert ServerSelector.server_arg_sets() == [["-L", "outer"], []]

      Application.put_env(:tmux_channel, :server_name, "inner")
      task = Task.async(fn -> ServerSelector.server_arg_sets() end)
      assert Task.await(task) == [["-L", "inner"], []]
    end
  end
end
