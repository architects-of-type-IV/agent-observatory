defmodule TmuxChannel.ServerSelector do
  @moduledoc """
  Discovers and caches the tmux server arguments to use for this process.

  The candidate list comes from `TmuxChannel.Config.server_arg_sets/0`. Building
  it touches the filesystem, so the result is cached in the process dictionary
  for `TmuxChannel.Config.server_cache_ttl_ms/0` milliseconds.

  The cache is per-process and expires on its own; `reset_cache/0` clears it
  eagerly, which is mostly useful in tests and after creating a socket.
  """

  @cache_key :tmux_channel_server_arg_sets

  @doc """
  Return the `[server_args, ...]` sets to try, in priority order.

  Each element is a list of flags suitable for prepending to a tmux command.
  """
  @spec server_arg_sets() :: [[String.t()]]
  def server_arg_sets do
    now = System.monotonic_time(:millisecond)
    ttl = TmuxChannel.Config.server_cache_ttl_ms()

    case Process.get(@cache_key) do
      {sets, ts} when now - ts < ttl ->
        sets

      _ ->
        sets = TmuxChannel.Config.server_arg_sets()
        Process.put(@cache_key, {sets, now})
        sets
    end
  end

  @doc """
  Return the server args for the first tmux server that answers `list-sessions`.

  Returns `[]` when none answer, which falls through to the default server.
  """
  @spec first_responsive() :: [String.t()]
  def first_responsive do
    Enum.find(server_arg_sets(), [], fn args ->
      match?({:ok, _}, TmuxChannel.Command.run(args ++ ["list-sessions"]))
    end)
  end

  @doc "Drop this process's cached server list so the next call rebuilds it."
  @spec reset_cache() :: :ok
  def reset_cache do
    Process.delete(@cache_key)
    :ok
  end
end
