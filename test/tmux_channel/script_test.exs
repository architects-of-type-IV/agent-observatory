defmodule TmuxChannel.ScriptTest do
  use ExUnit.Case, async: false

  alias TmuxChannel.Script

  setup do
    on_exit(fn ->
      Application.delete_env(:tmux_channel, :permission_profiles)
      Application.delete_env(:tmux_channel, :script_command)
      Application.delete_env(:tmux_channel, :model_flag)
    end)
  end

  describe "sanitize_name/1" do
    test "keeps alphanumerics, dashes, and underscores" do
      assert Script.sanitize_name("build_agent-01") == "build_agent-01"
    end

    test "strips path separators and spaces" do
      assert Script.sanitize_name("../../etc/passwd") == "etcpasswd"
      assert Script.sanitize_name("my agent!") == "myagent"
    end
  end

  describe "permission_args/1" do
    test "returns the configured profile" do
      Application.put_env(:tmux_channel, :permission_profiles, %{
        "scout" => ["--allowedTools", "Read"]
      })

      assert Script.permission_args("scout") == ["--allowedTools", "Read"]
    end

    test "returns an empty list for an unknown capability" do
      Application.put_env(:tmux_channel, :permission_profiles, %{"scout" => ["--x"]})
      assert Script.permission_args("nobody") == []
    end

    test "defaults give builder the skip-permissions flag and scout an allowlist" do
      assert "--dangerously-skip-permissions" in Script.permission_args("builder")
      assert "--allowedTools" in Script.permission_args("scout")
      refute "--dangerously-skip-permissions" in Script.permission_args("scout")
    end
  end

  describe "render_script/3" do
    test "pipes the prompt into the command and blocks afterwards" do
      script = Script.render_script("/tmp/p.txt", "opus", "builder")

      assert script =~ "#!/bin/sh\n"
      assert script =~ "cat '/tmp/p.txt' |"
      assert script =~ "'--model' 'opus'"
      assert String.ends_with?(script, "sleep infinity\n")
    end

    test "includes the capability's arguments" do
      Application.put_env(:tmux_channel, :permission_profiles, %{
        "scout" => ["--allowedTools", "Read"]
      })

      script = Script.render_script("/tmp/p.txt", "haiku", "scout")

      assert script =~ "'--allowedTools' 'Read'"
    end

    test "omits extra arguments for an unknown capability" do
      script = Script.render_script("/tmp/p.txt", "opus", "unknown")

      refute script =~ "--dangerously-skip-permissions"
      refute script =~ "--allowedTools"
    end

    test "honours a configured command and model flag" do
      Application.put_env(:tmux_channel, :script_command, "my-agent run")
      Application.put_env(:tmux_channel, :model_flag, "-m")
      script = Script.render_script("/tmp/p.txt", "x", "builder")

      assert script =~ "| my-agent run '-m' 'x'"
    end

    test "escapes single quotes so a hostile path cannot break out" do
      script = Script.render_script("/tmp/it's here/p.txt", "opus", "builder")

      assert script =~ ~S{cat '/tmp/it'\''s here/p.txt'}
      refute script =~ "; rm"
    end
  end

  describe "write_agent_files/5" do
    setup do
      dir =
        Path.join(System.tmp_dir!(), "tmux_channel_script_#{:erlang.unique_integer([:positive])}")

      on_exit(fn -> File.rm_rf!(dir) end)
      {:ok, dir: dir}
    end

    test "writes prompt and script, and makes the script executable", %{dir: dir} do
      assert {:ok, %{prompt_path: prompt, script_path: script}} =
               Script.write_agent_files(dir, "agent one", "do the thing", "opus", "builder")

      assert Path.basename(prompt) == "agentone.txt"
      assert Path.basename(script) == "agentone.sh"
      assert File.read!(prompt) == "do the thing"
      assert File.read!(script) =~ "cat '#{prompt}'"

      %File.Stat{mode: mode} = File.stat!(script)
      assert Bitwise.band(mode, 0o111) == 0o111
    end

    test "creates the base directory when missing", %{dir: dir} do
      nested = Path.join(dir, "deep/nested")
      assert {:ok, _} = Script.write_agent_files(nested, "a", "p", "opus", "builder")
      assert File.dir?(nested)
    end

    test "cleanup_agent_files removes both files and is idempotent", %{dir: dir} do
      {:ok, %{prompt_path: prompt, script_path: script}} =
        Script.write_agent_files(dir, "agent", "p", "opus", "builder")

      assert :ok = Script.cleanup_agent_files(dir, "agent")
      refute File.exists?(prompt)
      refute File.exists?(script)
      assert :ok = Script.cleanup_agent_files(dir, "agent")
    end

    test "cleanup_dir removes the tree and is idempotent", %{dir: dir} do
      {:ok, _} = Script.write_agent_files(dir, "agent", "p", "opus", "builder")

      assert :ok = Script.cleanup_dir(dir)
      refute File.dir?(dir)
      assert :ok = Script.cleanup_dir(dir)
    end
  end
end
