defmodule Ichor.Infrastructure.Tmux do
  @moduledoc """
  Delivers messages to agents via tmux named buffers and paste-buffer.
  Can also capture pane output for the unified activity stream.

  Tries multiple tmux server options in order:
    1. -S ~/.ichor/tmux/obs.sock (explicit socket path)
    2. -L obs (named server)
    3. default server

  Low-level command execution lives in `Tmux.Command`.
  Server discovery and caching lives in `Tmux.ServerSelector`.
  Output parsing lives in `Tmux.Parser`.
  """

  @behaviour Ichor.Infrastructure.Channel

  alias Ichor.Infrastructure.Tmux.Command
  alias Ichor.Infrastructure.Tmux.Parser
  alias Ichor.Infrastructure.Tmux.ServerSelector

  @impl true
  def channel_key, do: :tmux

  @impl true
  def skip?(payload) do
    payload[:type] in [:heartbeat, :system]
  end

  @impl true
  def deliver(session_name, payload) when is_binary(session_name) do
    content = payload[:content] || payload["content"] || Jason.encode!(payload)
    from = payload[:from] || payload["from"] || "ichor"
    message = "[#{from}] #{content}"

    # Use named tmux buffer + paste-buffer to inject text without triggering
    # file read permissions in the target pane (avoids cat /tmp/file approach).
    # Named buffer prevents concurrent deliveries from corrupting each other.
    buf_name = "obs-#{:erlang.unique_integer([:positive])}"

    with {:ok, _} <- Command.try_all(["set-buffer", "-b", buf_name, message]),
         {:ok, _} <- Command.try_all(["paste-buffer", "-b", buf_name, "-d", "-t", session_name]),
         _ = Process.sleep(150),
         {:ok, _} <- Command.try_all(["send-keys", "-t", session_name, "Enter"]) do
      :ok
    else
      {:error, reason} ->
        # Clean up named buffer on failure (best effort)
        Command.try_all(["delete-buffer", "-b", buf_name])
        {:error, {:tmux_send_failed, reason}}
    end
  end

  @impl true
  # Pane IDs start with %, session names don't
  def available?("%" <> _ = target),
    do: match?({:ok, _}, Command.try_all(["display-message", "-t", target, "-p", ""]))

  def available?(target) when is_binary(target),
    do: match?({:ok, _}, Command.try_all(["has-session", "-t", target]))

  @doc """
  Capture the current pane output from a tmux session.
  Returns `{:ok, output}` or `{:error, reason}`.

  Options:
    * `:ansi` - when `true`, preserves ANSI escape codes (`-e` flag). Default `false`.
  """
  @spec capture_pane(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def capture_pane(session_name, opts \\ []) do
    args =
      if Keyword.get(opts, :ansi, false),
        do: ["capture-pane", "-e", "-p", "-t", session_name],
        else: ["capture-pane", "-p", "-t", session_name]

    case Command.try_all(args) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, {:capture_failed, reason}}
    end
  end

  @pane_format "\#{pane_id}\t\#{session_name}\t\#{pane_title}\t\#{pane_pid}"

  @doc "List all panes across all known servers/sockets with pane_id, session, and title."
  @spec list_panes() :: [map()]
  def list_panes do
    ServerSelector.server_arg_sets()
    |> Enum.flat_map(fn args ->
      case Command.run(args ++ ["list-panes", "-a", "-F", @pane_format]) do
        {:ok, output} ->
          output
          |> Parser.split_lines()
          |> Enum.map(&Parser.parse_pane_line/1)
          |> Enum.reject(&is_nil/1)

        {:error, _} ->
          []
      end
    end)
    |> Enum.uniq_by(& &1.pane_id)
  end

  @doc "List all active tmux sessions across all known servers/sockets."
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    ServerSelector.server_arg_sets()
    |> Enum.flat_map(fn args ->
      case Command.run(args ++ ["list-sessions", "-F", "\#{session_name}"]) do
        {:ok, output} -> Parser.split_lines(output)
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc "List all windows in a session as `%{name: \"window-name\", target: \"session:window\"}`."
  @spec list_windows(String.t()) :: [%{name: String.t(), target: String.t()}]
  def list_windows(session) do
    case Command.try_all(["list-windows", "-t", session, "-F", "\#{window_name}"]) do
      {:ok, output} ->
        output
        |> Parser.split_lines()
        |> Enum.map(fn name -> %{name: name, target: "#{session}:#{name}"} end)

      {:error, _} ->
        []
    end
  end

  @doc """
  List all sessions with their windows.
  Returns `[%{session: "name", windows: [%{name: ..., target: ...}]}]`.
  """
  @spec list_sessions_with_windows() :: [%{session: String.t(), windows: list()}]
  def list_sessions_with_windows do
    list_sessions()
    |> Enum.map(fn session ->
      %{session: session, windows: list_windows(session)}
    end)
  end

  @doc "Run a tmux command across all known server options, return first success."
  @spec run_command([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def run_command(cmd_args), do: Command.try_all(cmd_args)

  @doc "Return tmux args for the first responsive ichor server."
  @spec socket_args() :: [String.t()]
  def socket_args, do: ServerSelector.first_responsive()
end
