defmodule Ichor.Fleet.Lifecycle.TmuxScriptTest do
  use ExUnit.Case, async: true

  alias Ichor.Fleet.Lifecycle.TmuxScript

  test "renders scout script with constrained tools" do
    script = TmuxScript.render_script("/tmp/prompt.txt", "sonnet", "scout")

    assert script =~ "claude --model sonnet"
    assert script =~ "--allowedTools"
    assert script =~ "WebSearch"
  end

  test "writes prompt and script files" do
    base_dir = Path.join(System.tmp_dir!(), "tmux-script-#{System.unique_integer([:positive])}")

    assert {:ok, %{prompt_path: prompt_path, script_path: script_path}} =
             TmuxScript.write_agent_files(base_dir, "agent-1", "hello", "sonnet", "builder")

    assert File.read!(prompt_path) == "hello"
    assert File.read!(script_path) =~ "dangerously-skip-permissions"

    assert :ok = TmuxScript.cleanup_dir(base_dir)
    refute File.exists?(base_dir)
  end
end
