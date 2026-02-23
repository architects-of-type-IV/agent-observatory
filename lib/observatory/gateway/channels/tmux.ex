defmodule Observatory.Gateway.Channels.Tmux do
  @moduledoc """
  Delivers messages to agents via tmux send-keys.
  Writes payload to a temp file and executes via send-keys to avoid escaping issues.
  Can also capture pane output for the unified activity stream.
  """

  @behaviour Observatory.Gateway.Channel

  require Logger

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")

  @impl true
  def deliver(session_name, payload) when is_binary(session_name) do
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "observatory"

    # Write message to temp file, then send via tmux
    tmp_path = "/tmp/observatory_msg_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}.txt"

    File.write!(tmp_path, "[#{from}] #{content}")

    args = socket_args() ++ ["send-keys", "-t", session_name, "cat #{tmp_path}", "Enter"]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {_output, 0} ->
        spawn(fn ->
          Process.sleep(5_000)
          File.rm(tmp_path)
        end)

        :ok

      {error, _code} ->
        # Retry on default server if Observatory socket failed
        case System.cmd("tmux", ["send-keys", "-t", session_name, "cat #{tmp_path}", "Enter"],
               stderr_to_stdout: true
             ) do
          {_output, 0} ->
            spawn(fn ->
              Process.sleep(5_000)
              File.rm(tmp_path)
            end)

            :ok

          _ ->
            File.rm(tmp_path)
            {:error, {:tmux_send_failed, error}}
        end
    end
  end

  @impl true
  def available?(session_name) when is_binary(session_name) do
    # Check Observatory socket first, fall back to default
    case System.cmd("tmux", socket_args() ++ ["has-session", "-t", session_name],
           stderr_to_stdout: true
         ) do
      {_output, 0} ->
        true

      _ ->
        case System.cmd("tmux", ["has-session", "-t", session_name], stderr_to_stdout: true) do
          {_output, 0} -> true
          _ -> false
        end
    end
  end

  @doc """
  Capture the current pane output from a tmux session.
  Returns {:ok, output_lines} or {:error, reason}.
  Strips ANSI escape codes from the output.
  """
  def capture_pane(session_name, opts \\ []) do
    lines = Keyword.get(opts, :lines, 50)
    base_args = ["-t", session_name, "-p", "-S", "-#{lines}"]

    # Try Observatory socket first, fall back to default
    args = socket_args() ++ ["capture-pane" | base_args]

    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} ->
        {:ok, strip_ansi(output)}

      _ ->
        case System.cmd("tmux", ["capture-pane" | base_args], stderr_to_stdout: true) do
          {output, 0} -> {:ok, strip_ansi(output)}
          {error, _code} -> {:error, {:capture_failed, error}}
        end
    end
  end

  @doc "List all active tmux sessions across all known sockets."
  def list_sessions do
    obs = list_sessions_on_socket(@observatory_socket)
    default = list_sessions_default()
    Enum.uniq(obs ++ default)
  end

  defp list_sessions_on_socket(socket_path) do
    if File.exists?(socket_path) do
      case System.cmd("tmux", ["-S", socket_path, "list-sessions", "-F", "\#{session_name}"],
             stderr_to_stdout: true
           ) do
        {output, 0} -> String.split(output, "\n", trim: true)
        _ -> []
      end
    else
      []
    end
  end

  defp list_sessions_default do
    case System.cmd("tmux", ["list-sessions", "-F", "\#{session_name}"],
           stderr_to_stdout: true
         ) do
      {output, 0} -> String.split(output, "\n", trim: true)
      _ -> []
    end
  end

  defp socket_args do
    if File.exists?(@observatory_socket),
      do: ["-S", @observatory_socket],
      else: []
  end

  # Strip ANSI escape codes using a regex
  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
