defmodule Ichor.Infrastructure.Tmux.Command do
  @moduledoc """
  Low-level tmux command execution helpers.

  Provides a thin wrapper around `System.cmd/3` for tmux, with consistent error
  handling and multi-server fallback via `ServerSelector`.

  All functions return `{:ok, output}` on exit code 0, or `{:error, reason}`
  otherwise.  Callers at higher layers should not need to inspect raw exit codes.
  """

  alias Ichor.Infrastructure.Tmux.ServerSelector

  @doc """
  Execute a tmux command, trying each known server in order.

  Returns the output of the first server that responds with exit code 0, or
  `{:error, :no_server}` if no server succeeds.
  """
  @spec try_all(list(String.t())) :: {:ok, String.t()} | {:error, term()}
  def try_all(cmd_args) do
    Enum.find_value(ServerSelector.server_arg_sets(), {:error, :no_server}, fn server_args ->
      case run(server_args ++ cmd_args) do
        {:ok, output} -> {:ok, output}
        {:error, :emfile} -> {:error, :emfile}
        {:error, _reason} -> nil
      end
    end)
  end

  @doc """
  Execute a single tmux command with explicit server args.

  Returns `{:ok, output}` on success, `{:error, reason}` on failure.
  """
  @spec run([String.t()]) :: {:ok, String.t()} | {:error, term()}
  def run(args) do
    case System.cmd("tmux", args, stderr_to_stdout: true) do
      {output, 0} -> {:ok, output}
      {output, code} -> {:error, {:tmux_failed, code, String.trim(output)}}
    end
  catch
    :error, :emfile -> {:error, :emfile}
    :exit, :emfile -> {:error, :emfile}
  end
end
