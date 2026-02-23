defmodule Observatory.Gateway.Channels.Tmux do
  @moduledoc """
  Delivers messages to agents via tmux send-keys.
  Writes payload to a temp file and executes via send-keys to avoid escaping issues.
  Can also capture pane output for the unified activity stream.
  """

  @behaviour Observatory.Gateway.Channel

  require Logger

  @impl true
  def deliver(session_name, payload) when is_binary(session_name) do
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "observatory"

    # Write message to temp file, then send via tmux
    tmp_path = "/tmp/observatory_msg_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}.txt"

    File.write!(tmp_path, "[#{from}] #{content}")

    case System.cmd("tmux", ["send-keys", "-t", session_name, "cat #{tmp_path}", "Enter"],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        # Schedule cleanup of temp file
        spawn(fn ->
          Process.sleep(5_000)
          File.rm(tmp_path)
        end)

        :ok

      {error, _code} ->
        File.rm(tmp_path)
        {:error, {:tmux_send_failed, error}}
    end
  end

  @impl true
  def available?(session_name) when is_binary(session_name) do
    case System.cmd("tmux", ["has-session", "-t", session_name], stderr_to_stdout: true) do
      {_output, 0} -> true
      _ -> false
    end
  end

  @doc """
  Capture the current pane output from a tmux session.
  Returns {:ok, output_lines} or {:error, reason}.
  Strips ANSI escape codes from the output.
  """
  def capture_pane(session_name, opts \\ []) do
    lines = Keyword.get(opts, :lines, 50)
    args = ["capture-pane", "-t", session_name, "-p", "-S", "-#{lines}"]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} ->
        cleaned = strip_ansi(output)
        {:ok, cleaned}

      {error, _code} ->
        {:error, {:capture_failed, error}}
    end
  end

  @doc "List all active tmux sessions. Returns list of session name strings."
  def list_sessions do
    # The format string is a tmux literal, not Elixir interpolation
    case System.cmd("tmux", ["list-sessions", "-F", "\#{session_name}"],
           stderr_to_stdout: true
         ) do
      {output, 0} ->
        output
        |> String.split("\n", trim: true)

      _ ->
        []
    end
  end

  # Strip ANSI escape codes using a regex
  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
