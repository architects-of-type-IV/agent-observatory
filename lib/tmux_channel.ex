defmodule TmuxChannel do
  @moduledoc """
  Delivers messages to processes running in tmux, and reads their output back.

  A `TmuxChannel.Channel` adapter whose addresses are tmux session names or pane
  ids. Beyond delivery it exposes the read side — capturing pane contents and
  listing sessions, windows, and panes — which is what makes it usable as an
  observability source and not just a transport.

  ## Delivery

  Text is injected with a *named* tmux buffer plus `paste-buffer`:

      set-buffer -b <buf> <message>
      paste-buffer -b <buf> -d -t <target>
      send-keys -t <target> Enter

  Writing the text to a temp file and having the target `cat` it would be
  simpler, but that trips file-read permission prompts in the target program.
  The buffer name is unique per delivery so concurrent sends cannot overwrite
  each other's text, and `-d` deletes the buffer once pasted.

  A short settle delay separates the paste from Enter — tmux pastes
  asynchronously, and sending Enter immediately submits an empty line. Tune it
  with `:paste_settle_ms`.

  ## Servers

  Reads are attempted against every server in `TmuxChannel.Config.server_arg_sets/0`
  (explicit socket, named server, default server) and the first success wins, so
  panes are found wherever they live. Session creation goes through
  `TmuxChannel.Launcher`, which targets one server deterministically.

  ## Configuration

  Nothing is required; see `TmuxChannel.Config` for the defaults and the keys
  that override them.

  ## Example

      iex> TmuxChannel.available?("my-session")
      false

      TmuxChannel.deliver("my-session", %{from: "scheduler", content: "status?"})
      {:ok, pane} = TmuxChannel.capture_pane("my-session")
  """

  @behaviour TmuxChannel.Channel

  alias TmuxChannel.Command
  alias TmuxChannel.Config
  alias TmuxChannel.Parser
  alias TmuxChannel.ServerSelector

  @pane_format "\#{pane_id}\t\#{session_name}\t\#{pane_title}\t\#{pane_pid}"

  @impl true
  def channel_key, do: :tmux

  @impl true
  def skip?(payload), do: payload[:type] in [:heartbeat, :system]

  @impl true
  @doc """
  Deliver a payload to a tmux session or pane.

  Reads `:content` and `:from` from the payload, accepting either atom or string
  keys; a payload with no content falls back to `inspect/1`. On failure the
  named buffer is deleted on a best-effort basis so it does not leak.
  """
  @spec deliver(String.t(), map()) :: :ok | {:error, term()}
  def deliver(target, payload) when is_binary(target) do
    content = payload[:content] || payload["content"] || inspect(payload)
    from = payload[:from] || payload["from"] || "system"
    message = "[#{from}] #{content}"
    buffer = "#{Config.buffer_prefix()}-#{:erlang.unique_integer([:positive])}"

    with {:ok, _} <- Command.try_all(["set-buffer", "-b", buffer, message]),
         {:ok, _} <- Command.try_all(["paste-buffer", "-b", buffer, "-d", "-t", target]),
         _ = Process.sleep(Config.paste_settle_ms()),
         {:ok, _} <- Command.try_all(["send-keys", "-t", target, "Enter"]) do
      :ok
    else
      {:error, reason} ->
        Command.try_all(["delete-buffer", "-b", buffer])
        {:error, {:tmux_send_failed, reason}}
    end
  end

  @impl true
  @doc """
  Whether a target is reachable.

  Pane ids start with `%` and are checked with `display-message`; anything else
  is treated as a session name and checked with `has-session`.
  """
  @spec available?(String.t()) :: boolean()
  def available?("%" <> _ = pane_id),
    do: match?({:ok, _}, Command.try_all(["display-message", "-t", pane_id, "-p", ""]))

  def available?(target) when is_binary(target),
    do: match?({:ok, _}, Command.try_all(["has-session", "-t", target]))

  @doc """
  Capture the visible pane contents of a session or pane.

  Pass `ansi: true` to keep ANSI escape sequences (tmux's `-e`), which is what
  you want when feeding a terminal emulator rather than reading plain text.
  """
  @spec capture_pane(String.t(), keyword()) :: {:ok, String.t()} | {:error, term()}
  def capture_pane(target, opts \\ []) do
    args =
      if Keyword.get(opts, :ansi, false),
        do: ["capture-pane", "-e", "-p", "-t", target],
        else: ["capture-pane", "-p", "-t", target]

    case Command.try_all(args) do
      {:ok, output} -> {:ok, output}
      {:error, reason} -> {:error, {:capture_failed, reason}}
    end
  end

  @doc "List every pane across all reachable servers, deduplicated by pane id."
  @spec list_panes() :: [TmuxChannel.Parser.pane()]
  def list_panes do
    ServerSelector.server_arg_sets()
    |> Enum.flat_map(fn server_args ->
      case Command.run(server_args ++ ["list-panes", "-a", "-F", @pane_format]) do
        {:ok, output} -> Parser.parse_panes(output)
        {:error, _} -> []
      end
    end)
    |> Enum.uniq_by(& &1.pane_id)
  end

  @doc "List every session name across all reachable servers, deduplicated."
  @spec list_sessions() :: [String.t()]
  def list_sessions do
    ServerSelector.server_arg_sets()
    |> Enum.flat_map(fn server_args ->
      case Command.run(server_args ++ ["list-sessions", "-F", "\#{session_name}"]) do
        {:ok, output} -> Parser.split_lines(output)
        {:error, _} -> []
      end
    end)
    |> Enum.uniq()
  end

  @doc ~S"""
  List the windows of a session as `%{name: "win", target: "session:win"}`.

  The `target` is pre-qualified so it can be passed straight back to any tmux
  command that takes `-t`.
  """
  @spec list_windows(String.t()) :: [%{name: String.t(), target: String.t()}]
  def list_windows(session) do
    case Command.try_all(["list-windows", "-t", session, "-F", "\#{window_name}"]) do
      {:ok, output} ->
        output
        |> Parser.split_lines()
        |> Enum.map(&%{name: &1, target: "#{session}:#{&1}"})

      {:error, _} ->
        []
    end
  end

  @doc "Every session paired with its windows."
  @spec list_sessions_with_windows() :: [%{session: String.t(), windows: [map()]}]
  def list_sessions_with_windows do
    Enum.map(list_sessions(), &%{session: &1, windows: list_windows(&1)})
  end

  @doc "Run an arbitrary tmux command, returning the first server that succeeds."
  @spec run_command([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def run_command(cmd_args), do: Command.try_all(cmd_args)

  @doc "Server args for the first responsive server, or `[]` if none respond."
  @spec socket_args() :: [String.t()]
  def socket_args, do: ServerSelector.first_responsive()
end
