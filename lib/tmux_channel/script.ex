defmodule TmuxChannel.Script do
  @moduledoc """
  Materializes the prompt file and launch script for a tmux-backed agent.

  `write_agent_files/5` writes two files into `base_dir`:

    * `<name>.txt` — the prompt, passed to the agent on stdin
    * `<name>.sh` — an executable launch script, mode 0755

  The script pipes the prompt into the configured agent command and then blocks
  forever, so the tmux window stays alive after the agent exits and its output
  remains readable.

  The command and the per-capability argument profiles are configurable — see
  `TmuxChannel.Config`.
  """

  @default_command "env -u CLAUDECODE claude"
  @default_model_flag "--model"

  @doc """
  Write the prompt and launch script for one agent.

  `file_name` is sanitized down to `[A-Za-z0-9_-]`, so callers can pass a
  display name directly. Returns the two paths written.
  """
  @spec write_agent_files(String.t(), String.t(), String.t(), String.t(), String.t()) ::
          {:ok, %{prompt_path: String.t(), script_path: String.t()}} | {:error, term()}
  def write_agent_files(base_dir, file_name, prompt, model, capability) do
    safe_name = sanitize_name(file_name)

    with :ok <- File.mkdir_p(base_dir),
         prompt_path = Path.join(base_dir, "#{safe_name}.txt"),
         script_path = Path.join(base_dir, "#{safe_name}.sh"),
         :ok <- File.write(prompt_path, prompt),
         script = render_script(prompt_path, model, capability),
         :ok <- File.write(script_path, script),
         :ok <- File.chmod(script_path, 0o755) do
      {:ok, %{prompt_path: prompt_path, script_path: script_path}}
    end
  end

  @doc "Remove a prompt directory and everything in it. Idempotent."
  @spec cleanup_dir(String.t()) :: :ok
  def cleanup_dir(dir) do
    if File.dir?(dir), do: File.rm_rf!(dir)
    :ok
  end

  @doc "Remove one agent's `.txt` and `.sh` files from `base_dir`. Idempotent."
  @spec cleanup_agent_files(String.t(), String.t()) :: :ok
  def cleanup_agent_files(base_dir, file_name) do
    safe_name = sanitize_name(file_name)

    Enum.each([".txt", ".sh"], fn ext ->
      path = Path.join(base_dir, "#{safe_name}#{ext}")
      if File.exists?(path), do: File.rm(path)
    end)
  end

  @doc """
  Render the launch script for a prompt file, model, and capability.

  The capability selects an argument profile from
  `TmuxChannel.Config.permission_profiles/0`; an unknown capability adds no
  extra arguments.
  """
  @spec render_script(String.t(), String.t(), String.t()) :: String.t()
  def render_script(prompt_path, model, capability) do
    cli_args =
      ([model_flag(), model] ++ permission_args(capability))
      |> Enum.map_join(" ", &shell_quote/1)

    """
    #!/bin/sh
    cat #{shell_quote(prompt_path)} | #{command()} #{cli_args}
    sleep infinity
    """
  end

  @doc "Strip a name down to the characters that are safe in a filename."
  @spec sanitize_name(String.t()) :: String.t()
  def sanitize_name(name), do: String.replace(name, ~r/[^a-zA-Z0-9_-]/, "")

  @doc "Extra CLI arguments for a capability, or `[]` when it has no profile."
  @spec permission_args(String.t()) :: [String.t()]
  def permission_args(capability) do
    TmuxChannel.Config.permission_profiles()
    |> Map.get(capability, [])
  end

  # Wrap in single quotes and escape any embedded single quote by closing the
  # quote, emitting an escaped one, and reopening: foo'bar -> 'foo'\''bar'
  defp shell_quote(arg) do
    "'" <> String.replace(arg, "'", "'\\''") <> "'"
  end

  defp command, do: Application.get_env(:tmux_channel, :script_command, @default_command)
  defp model_flag, do: Application.get_env(:tmux_channel, :model_flag, @default_model_flag)
end
