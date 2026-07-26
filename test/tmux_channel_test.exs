defmodule TmuxChannelTest do
  use ExUnit.Case, async: false

  alias TmuxChannel.Launcher
  alias TmuxChannel.ServerSelector

  describe "channel behaviour" do
    test "declares the tmux address key" do
      assert TmuxChannel.channel_key() == :tmux
    end

    test "implements the Channel behaviour" do
      behaviours =
        TmuxChannel.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert TmuxChannel.Channel in behaviours
    end

    test "skips heartbeat and system payloads" do
      assert TmuxChannel.skip?(%{type: :heartbeat})
      assert TmuxChannel.skip?(%{type: :system})
    end

    test "delivers everything else, including payloads with no type" do
      refute TmuxChannel.skip?(%{type: :message})
      refute TmuxChannel.skip?(%{content: "hello"})
      refute TmuxChannel.skip?(%{})
    end
  end

  describe "without a reachable server" do
    setup do
      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")

      Application.put_env(
        :tmux_channel,
        :server_name,
        "tc-absent-#{:erlang.unique_integer([:positive])}"
      )

      Application.put_env(:tmux_channel, :server_cache_ttl_ms, 0)
      ServerSelector.reset_cache()

      on_exit(fn ->
        for key <- [:socket_path, :server_name, :server_cache_ttl_ms] do
          Application.delete_env(:tmux_channel, key)
        end

        ServerSelector.reset_cache()
      end)
    end

    @tag :tmux
    test "available? is false for an unknown session and pane" do
      refute TmuxChannel.available?("no-such-session")
      refute TmuxChannel.available?("%99999")
    end

    @tag :tmux
    test "listings come back empty rather than raising" do
      assert TmuxChannel.list_sessions() == []
      assert TmuxChannel.list_panes() == []
      assert TmuxChannel.list_windows("no-such-session") == []
      assert TmuxChannel.list_sessions_with_windows() == []
    end

    @tag :tmux
    test "capture_pane reports a capture failure" do
      assert {:error, {:capture_failed, _}} = TmuxChannel.capture_pane("no-such-session")
    end

    @tag :tmux
    test "deliver reports a send failure" do
      assert {:error, {:tmux_send_failed, _}} =
               TmuxChannel.deliver("no-such-session", %{content: "hi"})
    end
  end

  describe "against a live tmux server" do
    @moduletag :tmux

    setup do
      server = "tc-test-#{:erlang.unique_integer([:positive])}"
      session = "sess-#{:erlang.unique_integer([:positive])}"

      Application.put_env(:tmux_channel, :socket_path, "/nonexistent/nope.sock")
      Application.put_env(:tmux_channel, :server_name, server)
      Application.put_env(:tmux_channel, :server_cache_ttl_ms, 0)
      ServerSelector.reset_cache()

      # `cat` echoes whatever is pasted into the pane, so delivery is observable.
      :ok = Launcher.create_session(session, System.tmp_dir!(), "main", "cat")

      on_exit(fn ->
        TmuxChannel.Command.run(["-L", server, "kill-server"])

        for key <- [:socket_path, :server_name, :server_cache_ttl_ms] do
          Application.delete_env(:tmux_channel, key)
        end

        ServerSelector.reset_cache()
      end)

      {:ok, server: server, session: session}
    end

    test "the session is visible and reachable", %{session: session} do
      assert session in TmuxChannel.list_sessions()
      assert TmuxChannel.available?(session)
      assert Launcher.available?(session)
    end

    test "windows are listed with a qualified target", %{session: session} do
      assert [%{name: "main", target: target}] = TmuxChannel.list_windows(session)
      assert target == "#{session}:main"
    end

    test "list_sessions_with_windows pairs them up", %{session: session} do
      entry = Enum.find(TmuxChannel.list_sessions_with_windows(), &(&1.session == session))

      assert %{windows: [%{name: "main"}]} = entry
    end

    test "panes are listed with an id and the owning session", %{session: session} do
      pane = Enum.find(TmuxChannel.list_panes(), &(&1.session == session))

      assert %{pane_id: "%" <> _, pid: pid} = pane
      assert pid =~ ~r/^\d+$/
    end

    test "a listed pane id is reachable", %{session: session} do
      pane = Enum.find(TmuxChannel.list_panes(), &(&1.session == session))

      assert TmuxChannel.available?(pane.pane_id)
    end

    test "adding a window shows up in the listing", %{session: session} do
      assert :ok = Launcher.create_window(session, "second", System.tmp_dir!(), "cat")

      names = TmuxChannel.list_windows(session) |> Enum.map(& &1.name) |> Enum.sort()
      assert names == ["main", "second"]
    end

    test "delivered text lands in the pane", %{session: session} do
      assert :ok = TmuxChannel.deliver(session, %{from: "scheduler", content: "ping-42"})

      assert eventually(fn ->
               {:ok, pane} = TmuxChannel.capture_pane(session)
               pane =~ "[scheduler] ping-42"
             end)
    end

    test "string payload keys work the same as atoms", %{session: session} do
      assert :ok = TmuxChannel.deliver(session, %{"from" => "api", "content" => "str-key"})

      assert eventually(fn ->
               {:ok, pane} = TmuxChannel.capture_pane(session)
               pane =~ "[api] str-key"
             end)
    end

    test "a payload with no content falls back to inspect", %{session: session} do
      assert :ok = TmuxChannel.deliver(session, %{ref: "abc123"})

      assert eventually(fn ->
               {:ok, pane} = TmuxChannel.capture_pane(session)
               pane =~ "abc123"
             end)
    end

    test "concurrent deliveries all arrive", %{session: session} do
      1..5
      |> Task.async_stream(
        fn n -> TmuxChannel.deliver(session, %{from: "t", content: "msg-#{n}"}) end,
        max_concurrency: 5
      )
      |> Enum.each(fn {:ok, result} -> assert result == :ok end)

      assert eventually(fn ->
               {:ok, pane} = TmuxChannel.capture_pane(session)
               Enum.all?(1..5, &(pane =~ "msg-#{&1}"))
             end)
    end

    test "capture_pane with ansi: true still returns the text", %{session: session} do
      assert {:ok, output} = TmuxChannel.capture_pane(session, ansi: true)
      assert is_binary(output)
    end

    test "run_command reaches the server", %{session: session} do
      assert {:ok, output} =
               TmuxChannel.run_command(["list-sessions", "-F", "\#{session_name}"])

      assert output =~ session
    end

    test "socket_args resolves to the configured named server", %{server: server} do
      assert TmuxChannel.socket_args() == ["-L", server]
    end

    test "kill_session removes it", %{session: session} do
      assert :ok = Launcher.kill_session(session)
      refute eventually(fn -> session in TmuxChannel.list_sessions() end, 5)
    end
  end

  defp eventually(fun, attempts \\ 40) do
    Enum.reduce_while(1..attempts, false, fn _, _ ->
      if fun.() do
        {:halt, true}
      else
        Process.sleep(50)
        {:cont, false}
      end
    end)
  end
end
