defmodule Ichor.Infrastructure.Tmux.ServerSelector do
  @moduledoc """
  Discovers and caches the available tmux server arguments for this process.

  Tries the following tmux server options in priority order:

    1. `-S ~/.ichor/tmux/obs.sock` — explicit socket path (if the file exists)
    2. `-L obs` — named server
    3. `[]` — default server

  Results are cached per-process for `@ttl_ms` to avoid hammering the filesystem
  on every call.
  """

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")
  @ichor_server "obs"
  @ttl_ms 5_000

  @doc """
  Return the list of `[server_args, ...]` sets to try in order.

  Each element is a list of flags suitable for prepending to a `tmux` command.
  """
  @spec server_arg_sets() :: [[String.t()]]
  def server_arg_sets do
    cached = Process.get(:tmux_server_arg_sets_cache)
    now = System.monotonic_time(:millisecond)

    case cached do
      {sets, ts} when now - ts < @ttl_ms ->
        sets

      _ ->
        sets = build_server_arg_sets()
        Process.put(:tmux_server_arg_sets_cache, {sets, now})
        sets
    end
  end

  @doc """
  Return the server args for the first responsive ichor tmux server.

  Returns `[]` when no server responds (falls through to default server args).
  """
  @spec first_responsive() :: [String.t()]
  def first_responsive do
    Enum.find(server_arg_sets(), [], fn args ->
      case System.cmd("tmux", args ++ ["list-sessions"], stderr_to_stdout: true) do
        {_, 0} -> true
        _ -> false
      end
    end)
  end

  defp build_server_arg_sets do
    [
      if(File.exists?(@ichor_socket), do: ["-S", @ichor_socket]),
      ["-L", @ichor_server],
      []
    ]
    |> Enum.reject(&is_nil/1)
  end
end
