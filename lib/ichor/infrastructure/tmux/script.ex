defmodule Ichor.Infrastructure.Tmux.Script do
  @moduledoc """
  Materializes prompt and launch script files for tmux-backed agents.
  """

  @doc "Write the prompt file and launch shell script for an agent to `base_dir`."
  @spec write_agent_files(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, map()} | {:error, term()}
  def write_agent_files(base_dir, file_name, prompt, model, capability) do
    safe_name = sanitize_name(file_name)

    with :ok <- File.mkdir_p(base_dir),
         prompt_path <- Path.join(base_dir, "#{safe_name}.txt"),
         script_path <- Path.join(base_dir, "#{safe_name}.sh"),
         :ok <- File.write(prompt_path, prompt),
         script = render_script(prompt_path, model, capability),
         :ok <- File.write(script_path, script),
         :ok <- File.chmod(script_path, 0o755) do
      {:ok, %{prompt_path: prompt_path, script_path: script_path}}
    end
  end

  @doc "Remove a prompt directory and its contents if it exists."
  @spec cleanup_dir(String.t()) :: :ok
  def cleanup_dir(dir) do
    if File.dir?(dir) do
      File.rm_rf!(dir)
    end

    :ok
  end

  @doc "Remove the .txt and .sh files for a single agent from `base_dir`. Idempotent."
  @spec cleanup_agent_files(String.t(), String.t()) :: :ok
  def cleanup_agent_files(base_dir, file_name) do
    safe_name = sanitize_name(file_name)

    Enum.each([".txt", ".sh"], fn ext ->
      path = Path.join(base_dir, "#{safe_name}#{ext}")
      if File.exists?(path), do: File.rm(path)
    end)
  end

  @doc "Render the shell script that launches Claude with the given prompt, model, and capability."
  @spec render_script(String.t(), String.t(), String.t()) :: String.t()
  def render_script(prompt_path, model, capability) do
    cli_args =
      ["--model", model]
      |> add_permission_args(capability)
      |> Enum.join(" ")

    "#!/bin/sh\ncat '#{prompt_path}' | env -u CLAUDECODE claude #{cli_args}\nsleep infinity\n"
  end

  defp sanitize_name(name) do
    String.replace(name, ~r/[^a-zA-Z0-9_-]/, "")
  end

  defp add_permission_args(args, cap) when cap in ["builder", "lead", "coordinator"],
    do: args ++ ["--dangerously-skip-permissions"]

  defp add_permission_args(args, "scout"),
    do:
      args ++
        [
          "--allowedTools",
          "Read",
          "Glob",
          "Grep",
          "WebSearch",
          "WebFetch",
          "Bash",
          "mcp__ichor__check_inbox",
          "mcp__ichor__send_message",
          "mcp__ichor__acknowledge_message"
        ]

  defp add_permission_args(args, _), do: args
end
