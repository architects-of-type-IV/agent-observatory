defmodule Ichor.QualityGate do
  @moduledoc """
  Enforces quality gates when agents report task completion.

  Exposes `check/3` for direct quality gate invocation. The `done_when`
  command is run in a subprocess; on failure, a nudge is sent to the agent
  via tmux/mailbox.

  Inspired by Overstory's quality gate enforcement system.
  """
  use GenServer
  require Logger

  alias Ichor.Messages.Bus

  @default_timeout 60_000

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Manually trigger a quality gate check for a session."
  @spec check(String.t(), String.t(), keyword()) :: {:ok, :passed} | {:error, String.t()}
  def check(session_id, command, opts \\ []) do
    GenServer.call(__MODULE__, {:check, session_id, command, opts}, @default_timeout + 5_000)
  end

  @impl true
  def init(_opts) do
    {:ok, %{}}
  end

  @impl true
  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:check, session_id, command, opts}, _from, state) do
    result = run_gate(session_id, command, opts)
    {:reply, result, state}
  end

  defp run_gate(session_id, command, opts) do
    cwd = Keyword.get(opts, :cwd, File.cwd!())

    case run_gate_command(command, cwd) do
      {:ok, :passed} ->
        {:ok, :passed}

      {:error, output} ->
        nudge_agent(session_id, nil, command, output)
        {:error, output}
    end
  end

  defp run_gate_command(command, cwd) do
    case System.cmd("bash", ["-c", command], cd: cwd, stderr_to_stdout: true) do
      {_output, 0} ->
        {:ok, :passed}

      {output, _code} ->
        {:error, String.trim(output)}
    end
  rescue
    e -> {:error, "Gate command crashed: #{Exception.message(e)}"}
  end

  defp nudge_agent(session_id, task_id, command, output) do
    truncated = String.slice(output, -500, 500)
    task_ref = if task_id, do: " (task #{task_id})", else: ""

    message =
      "[Ichor Quality Gate FAILED]#{task_ref}\n" <>
        "Command: #{command}\n" <>
        "Output:\n#{truncated}\n\n" <>
        "Fix the issues and re-run the gate before reporting completion."

    _ =
      Bus.send(%{
        from: "ichor",
        to: session_id,
        content: message,
        type: :quality_gate
      })

    :ok
  end
end
