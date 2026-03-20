defmodule Ichor.Infrastructure.Tmux.Ssh do
  @moduledoc """
  Delivers messages to agents in tmux sessions on remote hosts via SSH.

  Address format: `"session_name@host"` where host is an SSH-reachable hostname
  (matching an entry in `~/.ssh/config` or a bare `user@host`).

  Uses the same named-buffer + paste-buffer approach as the local Tmux adapter,
  wrapped in `ssh -o ConnectTimeout=5`. Requires passwordless SSH (key-based auth).

  Configuration:

      config :ichor, Ichor.Infrastructure.Tmux.Ssh,
        connect_timeout: 5,
        socket_path: "/tmp/obs.sock",
        ssh_opts: ["-o", "StrictHostKeyChecking=accept-new"]
  """

  @behaviour Ichor.Gateway.Channel

  alias Ichor.Gateway.Channels.AnsiUtils

  @impl true
  def channel_key, do: :ssh_tmux

  @impl true
  def skip?(payload) do
    payload[:type] in [:heartbeat, :system]
  end

  @impl true
  def deliver(address, payload) when is_binary(address) do
    {session_name, host} = parse_address(address)
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "ichor"
    message = "[#{from}] #{content}"

    buf_name = "obs-#{:erlang.unique_integer([:positive])}"

    with {:ok, _} <- ssh_tmux(host, ["set-buffer", "-b", buf_name, message]),
         {:ok, _} <- ssh_tmux(host, ["paste-buffer", "-b", buf_name, "-d", "-t", session_name]),
         {:ok, _} <- ssh_tmux(host, ["send-keys", "-t", session_name, "Enter"]) do
      :ok
    else
      {:error, reason} ->
        ssh_tmux(host, ["delete-buffer", "-b", buf_name])
        {:error, {:ssh_tmux_send_failed, host, reason}}
    end
  end

  @impl true
  def available?(address) when is_binary(address) do
    {session_name, host} = parse_address(address)
    match?({:ok, _}, ssh_tmux(host, ["has-session", "-t", session_name]))
  end

  @doc "Capture pane output from a remote tmux session."
  @spec capture_pane(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def capture_pane(address, opts \\ []) do
    {session_name, host} = parse_address(address)
    lines = Keyword.get(opts, :lines, 50)

    case ssh_tmux(host, ["capture-pane", "-t", session_name, "-p", "-S", "-#{lines}"]) do
      {:ok, output} -> {:ok, AnsiUtils.strip_ansi(output)}
      {:error, reason} -> {:error, {:capture_failed, host, reason}}
    end
  end

  @doc "List tmux sessions on a remote host."
  @spec list_sessions(String.t()) :: [String.t()]
  def list_sessions(host) do
    case ssh_tmux(host, ["list-sessions", "-F", "\#{session_name}"]) do
      {:ok, output} -> String.split(output, "\n", trim: true)
      {:error, _} -> []
    end
  end

  defp parse_address(address) do
    case String.split(address, "@", parts: 2) do
      [session, host] -> {session, host}
      [session] -> {session, "localhost"}
    end
  end

  defp ssh_tmux(host, tmux_args) do
    config = Application.get_env(:ichor, __MODULE__, [])
    timeout = Keyword.get(config, :connect_timeout, 5)
    socket_path = Keyword.get(config, :socket_path, "/tmp/obs.sock")
    extra_ssh_opts = Keyword.get(config, :ssh_opts, [])

    ssh_opts =
      [
        "-o",
        "ConnectTimeout=#{timeout}",
        "-o",
        "BatchMode=yes"
      ] ++ extra_ssh_opts

    # Build remote tmux command with socket
    tmux_cmd = build_tmux_command(socket_path, tmux_args)

    args = ssh_opts ++ [host, tmux_cmd]

    case System.cmd("ssh", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, String.trim(output)}
    end
  rescue
    e -> {:error, Exception.message(e)}
  end

  defp build_tmux_command(socket_path, tmux_args) do
    # Shell-escape each argument for the remote command
    escaped = Enum.map(tmux_args, &shell_escape/1)
    "tmux -S #{shell_escape(socket_path)} #{Enum.join(escaped, " ")}"
  end

  defp shell_escape(str) do
    if String.contains?(str, [" ", "'", "\"", "\\", "$", "`", "!", "\n"]) do
      "'#{String.replace(str, "'", "'\\''")}'"
    else
      str
    end
  end
end
