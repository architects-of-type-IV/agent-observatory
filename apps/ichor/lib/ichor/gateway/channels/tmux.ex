defmodule Ichor.Gateway.Channels.Tmux do
  @moduledoc """
  Delivers messages to agents via tmux named buffers and paste-buffer.
  Can also capture pane output for the unified activity stream.

  Tries multiple tmux server options in order:
    1. -S ~/.ichor/tmux/obs.sock (explicit socket path)
    2. -L obs (named server)
    3. default server
  """

  @behaviour Ichor.Gateway.Channel

  require Logger

  @impl true
  def channel_key, do: :tmux

  @impl true
  def skip?(payload) do
    payload[:type] in [:heartbeat, :system]
  end

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")
  @ichor_server "obs"
  @server_arg_sets_ttl_ms 5_000

  @impl true
  def deliver(session_name, payload) when is_binary(session_name) do
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "ichor"
    message = "[#{from}] #{content}"

    # Use named tmux buffer + paste-buffer to inject text without triggering
    # file read permissions in the target pane (avoids cat /tmp/file approach).
    # Named buffer prevents concurrent deliveries from corrupting each other.
    buf_name = "obs-#{:erlang.unique_integer([:positive])}"

    with {:ok, _} <- try_tmux(["set-buffer", "-b", buf_name, message]),
         {:ok, _} <- try_tmux(["paste-buffer", "-b", buf_name, "-d", "-t", session_name]),
         _ = Process.sleep(150),
         {:ok, _} <- try_tmux(["send-keys", "-t", session_name, "Enter"]) do
      :ok
    else
      {:error, reason} ->
        # Clean up named buffer on failure (best effort)
        try_tmux(["delete-buffer", "-b", buf_name])
        {:error, {:tmux_send_failed, reason}}
    end
  end

  @impl true
  # Pane IDs start with %, session names don't
  def available?("%" <> _ = target),
    do: match?({:ok, _}, try_tmux(["display-message", "-t", target, "-p", ""]))

  def available?(target) when is_binary(target),
    do: match?({:ok, _}, try_tmux(["has-session", "-t", target]))

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
          |> Enum.map(&parse_pane_line/1)
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

  @doc "Run a tmux command across all known server options, return first success."
  def run_command(cmd_args), do: try_tmux(cmd_args)

  @doc "Return tmux args for the first responsive ichor server."
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
    cached = Process.get(:tmux_server_arg_sets_cache)
    now = System.monotonic_time(:millisecond)

    case cached do
      {sets, ts} when now - ts < @server_arg_sets_ttl_ms ->
        sets

      _ ->
        sets =
          [
            if(File.exists?(@ichor_socket), do: ["-S", @ichor_socket]),
            ["-L", @ichor_server],
            []
          ]
          |> Enum.reject(&is_nil/1)

        Process.put(:tmux_server_arg_sets_cache, {sets, now})
        sets
    end
  end

  defp parse_pane_line(line) do
    case String.split(line, "\t") do
      [pane_id, session, title, pid] ->
        %{pane_id: pane_id, session: session, title: title, pid: pid}

      [pane_id, session, title] ->
        %{pane_id: pane_id, session: session, title: title, pid: nil}

      _ ->
        nil
    end
  end

  defp strip_ansi(text) do
    Regex.replace(~r/\e\[[0-9;]*[a-zA-Z]/, text, "")
  end
end
