defmodule Ichor.Dag.Spawner do
  @moduledoc """
  Spawns a DAG execution run for a Genesis Node.
  Creates Run + Jobs, validates, launches lead agent in tmux,
  starts RunProcess lifecycle monitor.
  """

  alias Ichor.Dag.{Loader, Prompts, RunSupervisor, Validator}
  alias Ichor.Genesis.{ModeRunner, ModeSpawner}
  alias Ichor.Signals

  @spec spawn(String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(node_id, project_id) do
    tmux_session = "dag-#{short_id()}"
    brief = ModeSpawner.load_project_brief(project_id)

    with {:ok, run} <- Loader.from_genesis(node_id, tmux_session: tmux_session),
         {:ok, _report} <- validate(run.id),
         lead = build_lead(run.id, tmux_session, node_id, brief, run.project_path),
         :ok <- ModeRunner.write_agent_scripts(run.id, "dag", [lead]),
         :ok <-
           ModeRunner.create_session_with_agent(tmux_session, File.cwd!(), run.id, "dag", lead) do
      ModeRunner.register_agent(tmux_session, lead, tmux_session, run.id, File.cwd!())

      RunSupervisor.start_run(
        run_id: run.id,
        tmux_session: tmux_session,
        project_path: run.project_path
      )

      Signals.emit(:dag_run_ready, %{
        run_id: run.id,
        session: tmux_session,
        node_id: node_id
      })

      {:ok, %{session: tmux_session, run: run}}
    else
      {:error, reason} ->
        Signals.emit(:dag_tmux_gone, %{run_id: "spawn_failed", session: tmux_session})
        {:error, reason}
    end
  end

  defp build_lead(run_id, session, node_id, brief, project_path) do
    %{
      name: "lead",
      capability: "lead",
      prompt:
        Prompts.dag_lead(%{
          run_id: run_id,
          session: session,
          node_id: node_id,
          brief: brief,
          project_path: project_path
        })
    }
  end

  defp validate(run_id) do
    case Ichor.Dag.Job.by_run(run_id) do
      {:ok, jobs} ->
        items = Enum.map(jobs, &Ichor.Dag.Graph.to_graph_node/1)
        cycles = Validator.detect_cycles(items)
        missing = Validator.flat_dag_check(items)

        if cycles == [] and missing == [] do
          {:ok, %{cycles: [], missing_refs: []}}
        else
          {:error, %{cycles: cycles, missing_refs: missing}}
        end

      error ->
        error
    end
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
