defmodule Ichor.Dag.Spawner do
  @moduledoc """
  Spawns a DAG execution team: coordinator + lead.
  Workers are spawned dynamically by the lead via spawn_agent MCP tool.
  Follows the Genesis ModeSpawner pattern: all upfront agents via ModeRunner.
  """

  alias Ichor.Dag.{Loader, Prompts, RunSupervisor, Validator}
  alias Ichor.Genesis.{ModeRunner, ModeSpawner}
  alias Ichor.Signals

  @spec spawn(String.t(), String.t()) ::
          {:ok, %{session: String.t(), run: map()}} | {:error, term()}
  def spawn(node_id, project_id) do
    run_id = short_id()
    session = "dag-#{run_id}"
    cwd = File.cwd!()
    brief = ModeSpawner.load_project_brief(project_id)

    with {:ok, run} <- Loader.from_genesis(node_id, tmux_session: session),
         {:ok, _report} <- validate(run.id),
         agents = build_agents(run.id, session, node_id, brief),
         :ok <- ModeRunner.write_agent_scripts(run.id, "dag", agents),
         :ok <- ModeRunner.create_session_with_agent(session, cwd, run.id, "dag", hd(agents)),
         :ok <- ModeRunner.create_remaining_windows(session, cwd, run.id, "dag", tl(agents)) do
      Enum.each(agents, &ModeRunner.register_agent(session, &1, session, run.id, cwd))

      RunSupervisor.start_run(
        run_id: run.id,
        tmux_session: session,
        project_path: run.project_path
      )

      Signals.emit(:dag_run_ready, %{
        run_id: run.id,
        session: session,
        node_id: node_id,
        agent_count: length(agents)
      })

      {:ok, %{session: session, run: run}}
    else
      {:error, reason} ->
        {:error, reason}
    end
  end

  defp build_agents(run_id, session, node_id, brief) do
    roster = team_roster(session)

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt:
          Prompts.coordinator(%{run_id: run_id, session: session, roster: roster, brief: brief})
      },
      %{
        name: "lead",
        capability: "lead",
        prompt:
          Prompts.lead(%{
            run_id: run_id,
            session: session,
            node_id: node_id,
            roster: roster,
            brief: brief
          })
      }
    ]
  end

  defp team_roster(session) do
    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
      - coordinator: #{session}-coordinator
      - lead: #{session}-lead
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end

  defp validate(run_id) do
    case Ichor.Dag.Job.by_run(run_id) do
      {:ok, jobs} ->
        items = Enum.map(jobs, &Ichor.Dag.Graph.to_graph_node/1)
        cycles = Validator.detect_cycles(items)
        missing = Validator.flat_dag_check(items)

        case {cycles, missing} do
          {[], []} -> {:ok, %{cycles: [], missing_refs: []}}
          _ -> {:error, %{cycles: cycles, missing_refs: missing}}
        end

      error ->
        error
    end
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
