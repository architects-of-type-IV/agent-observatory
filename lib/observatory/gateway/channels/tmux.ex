defmodule Observatory.Gateway.Channels.Tmux do
  @moduledoc """
  Delivers messages to agents via tmux send-keys.
  Writes payload to a temp file and executes via send-keys to avoid escaping issues.
  Can also capture pane output for the unified activity stream.

  Tries multiple tmux server options in order:
    1. -S ~/.observatory/tmux/obs.sock (explicit socket path)
    2. -L obs (named server)
    3. default server
  """

  @behaviour Observatory.Gateway.Channel

  require Logger

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")
  @observatory_server "obs"

  @impl true
  def deliver(session_name, payload) when is_binary(session_name) do
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "observatory"
    message = "[#{from}] #{content}"

    # Use tmux load-buffer + paste-buffer to inject text without triggering
    # file read permissions in the target pane (avoids cat /tmp/file approach)
    case try_tmux(["set-buffer", message]) do
      {:ok, _} ->
        case try_tmux(["paste-buffer", "-t", session_name]) do
          {:ok, _} ->
            # Send Enter to submit the pasted text
            try_tmux(["send-keys", "-t", session_name, "Enter"])
            :ok

          {:error, reason} ->
            {:error, {:tmux_send_failed, reason}}
        end

      {:error, reason} ->
        {:error, {:tmux_send_failed, reason}}
    end
  end

  @impl true
  def available?(target) when is_binary(target) do
    # Pane IDs start with %, session names don't
    if String.starts_with?(target, "%") do
      # For pane targets, check if the pane exists via list-panes
      match?({:ok, _}, try_tmux(["display-message", "-t", target, "-p", ""]))
    else
      match?({:ok, _}, try_tmux(["has-session", "-t", target]))
    end
  end

  @doc """
  Capture the current pane output from a tmux session.
  Returns {:ok, output_lines} or {:error, reason}.
  Strips ANSI escape codes from the output.
  """
  def capture_pane(session_name, opts \\ []) do
    lines = Keyword.get(opts, :lines, 50)

    case try_tmux(["capture-pane", "-t", session_name, "-p", "-S", "-#{lines}"]) do
      {:ok, output} -> {:ok, strip_ansi(output)}
      {:error, reason} -> {:error, {:capture_failed, reason}}
    end
  end

  @pane_format "\#{pane_id}\t\#{session_name}\t\#{pane_title}\t\#{pane_pid}"

  @doc "List all panes across all known servers/sockets with pane_id, session, and title."
  def list_panes do
    server_arg_sets()
    |> Enum.flat_map(fn args ->
      case System.cmd("tmux", args ++ ["list-panes", "-a", "-F", @pane_format],
             stderr_to_stdout: true
           ) do
        {output, 0} ->
          output
          |> String.split("\n", trim: true)
          |> Enum.map(fn line ->
            case String.split(line, "\t") do
              [pane_id, session, title, pid] ->
                %{pane_id: pane_id, session: session, title: title, pid: pid}

              [pane_id, session, title] ->
                %{pane_id: pane_id, session: session, title: title, pid: nil}

              _ ->
                nil
            end
          end)
          |> Enum.reject(&is_nil/1)

        _ ->
          []
      end
    end)
    |> Enum.uniq_by(& &1.pane_id)
  end

  @doc "List all active tmux sessions across all known servers/sockets."
  def list_sessions do
    server_arg_sets()
    |> Enum.flat_map(fn args ->
      case System.cmd("tmux", args ++ ["list-sessions", "-F", "\#{session_name}"],
             stderr_to_stdout: true
           ) do
        {output, 0} -> String.split(output, "\n", trim: true)
        _ -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "Return tmux args for the first responsive observatory server."
  def socket_args do
    Enum.find(server_arg_sets(), [], fn args ->
      case System.cmd("tmux", args ++ ["list-sessions"], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    end)
  end

  # Try a tmux command across all known server options, return first success.
  defp try_tmux(cmd_args) do
    Enum.find_value(server_arg_sets(), {:error, :no_server}, fn server_args ->
      case System.cmd("tmux", server_args ++ cmd_args, stderr_to_stdout: true) do
        {output, 0} -> {:ok, output}
        _ -> nil
      end
    end)
  end

  defp server_arg_sets do
    [
      if(File.exists?(@observatory_socket), do: ["-S", @observatory_socket]),
      ["-L", @observatory_server],
      []
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
