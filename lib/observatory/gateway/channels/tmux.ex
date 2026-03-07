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

    tmp_path = "/tmp/observatory_msg_#{:crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)}.txt"
    File.write!(tmp_path, "[#{from}] #{content}")

    case try_tmux(["send-keys", "-t", session_name, "cat #{tmp_path}", "Enter"]) do
      {:ok, _} ->
        spawn(fn ->
          Process.sleep(5_000)
          File.rm(tmp_path)
        end)

        :ok

      {:error, reason} ->
        File.rm(tmp_path)
        {:error, {:tmux_send_failed, reason}}
    end
  end

  @impl true
  def available?(session_name) when is_binary(session_name) do
    match?({:ok, _}, try_tmux(["has-session", "-t", session_name]))
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
