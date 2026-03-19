defmodule Ichor.QualityGate do
  @moduledoc """
  Enforces quality gates when agents report task completion.

  Listens for TaskCompleted hook events and runs the task's `done_when`
  command. If the gate fails, sends a nudge back to the agent via
  tmux/mailbox with the failure output.

  Inspired by Overstory's quality gate enforcement system.
  """
  use GenServer
  require Logger

  alias Ichor.Dag.Status

  @default_timeout 60_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Manually trigger a quality gate check for a session."
  @spec check(String.t(), String.t(), keyword()) :: {:ok, :passed} | {:error, String.t()}
  def check(session_id, command, opts \\ []) do
    GenServer.call(__MODULE__, {:check, session_id, command, opts}, @default_timeout + 5_000)
  end

  @impl true
  def init(_opts) do
    Phoenix.PubSub.subscribe(Ichor.PubSub, "events:stream")
    {:ok, %{}}
  end

  @impl true
  def handle_info({:new_event, event}, state) do
    if event.hook_event_type == :TaskCompleted do
      handle_task_completed(event)
    end

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:check, session_id, command, opts}, _from, state) do
    result = run_gate(session_id, command, opts)
    {:reply, result, state}
  end



  defp handle_task_completed(event) do
    session_id = event.session_id
    payload = event.payload || %{}

    # Try to find the task's done_when from the DAG runtime state
    task_id = payload["task_id"]
    done_when = find_done_when(task_id, event)

    if done_when && done_when != "" do
      Task.start(fn ->
        run_gate_async(session_id, task_id, done_when, event.cwd || File.cwd!())
      end)
    end
  end

  defp run_gate_async(session_id, task_id, done_when, cwd) do
    case run_gate_command(done_when, cwd) do
      {:ok, :passed} ->
        Logger.info("QualityGate: Gate passed for session #{session_id}, task #{task_id}")
        Ichor.Signals.emit(:gate_passed, %{session_id: session_id, task_id: task_id})

      {:error, output} ->
        Logger.warning(
          "QualityGate: Gate FAILED for session #{session_id}, task #{task_id}: #{String.slice(output, 0, 200)}"
        )

        nudge_agent(session_id, task_id, done_when, output)

        Ichor.Signals.emit(:gate_failed, %{
          session_id: session_id,
          task_id: task_id,
          output: output
        })
    end
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
      Ichor.MessageRouter.send(%{
        from: "ichor",
        to: session_id,
        content: message,
        type: :quality_gate
      })

    :ok
  end

  defp find_done_when(nil, _event), do: nil

  defp find_done_when(task_id, event) do
    dag_state = Status.state()
    tasks = dag_state[:tasks] || []

    case Enum.find(tasks, fn t -> to_string(t["id"]) == to_string(task_id) end) do
      %{"done_when" => done_when} when is_binary(done_when) -> done_when
      _ -> event.payload["done_when"]
    end
  end
end
