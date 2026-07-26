defmodule TmuxChannel.Command do
  @moduledoc """
  Low-level tmux command execution.

  A thin wrapper around `System.cmd/3` with consistent error handling and
  multi-server fallback. Every function returns `{:ok, output}` on exit code 0
  and `{:error, reason}` otherwise, so callers never inspect raw exit codes.
  """

  @doc """
  Execute a tmux command against each known server in order.

  Returns the output of the first server that exits 0, or `{:error, :no_server}`
  when none succeed. An `:emfile` (out of file descriptors) result short-circuits
  the remaining servers, since retrying cannot help.
  """
  @spec try_all([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def try_all(cmd_args) do
    Enum.find_value(TmuxChannel.ServerSelector.server_arg_sets(), {:error, :no_server}, fn args ->
      case run(args ++ cmd_args) do
        {:ok, output} -> {:ok, output}
        {:error, :emfile} -> {:error, :emfile}
        {:error, _reason} -> nil
      end
    end)
  end

  @doc """
  Execute a single tmux command with fully explicit arguments.

  Returns `{:ok, output}` on exit code 0, `{:error, {:tmux_failed, code, output}}`
  on a non-zero exit, `{:error, :emfile}` when the VM is out of file descriptors,
  and `{:error, :tmux_not_found}` when no `tmux` binary is on `PATH`.
  """
  @spec run([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def run(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:tmux_failed, code, String.trim(output)}}
    end
  rescue
    ErlangError -> {:error, :tmux_not_found}
  catch
    :error, :emfile -> {:error, :emfile}
    :exit, :emfile -> {:error, :emfile}
  end
end
