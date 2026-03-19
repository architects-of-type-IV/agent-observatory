defmodule Ichor.Projects.DagTeamSpecBuilder do
  @moduledoc """
  Pure builder for DAG execution team `TeamSpec` and `AgentSpec` runtime contracts.

  Patterns after `Ichor.Projects.TeamSpecBuilder` (MES builder).
  The "dag" preset supplies coordinator + lead. Workers are injected at runtime
  from the computed worker groups so each group gets its own pre-spawned window.
  """

  alias Ichor.Control.BlueprintState
  alias Ichor.Control.Presets
  alias Ichor.Control.TeamSpecBuilder, as: WorkshopTeamSpecBuilder
  alias Ichor.Projects.DagPrompts

  @doc "Build a `TeamSpec` for a DAG run from runtime context."
  @spec build_team_spec(map(), String.t(), String.t(), [map()], [map()], map()) ::
          Ichor.Control.Lifecycle.TeamSpec.t()
  def build_team_spec(run, session, brief, jobs, worker_groups, prompt_ctx) do
    state = dag_state(session, worker_groups)

    shared = %{
      run_id: run.id,
      session: session,
      brief: brief,
      jobs: jobs,
      worker_groups: worker_groups,
      subsystem_dir: prompt_ctx.subsystem_dir
    }

    roster = build_roster(session, worker_groups)
    prompt_by_name = build_prompt_map(shared, roster, worker_groups)

    WorkshopTeamSpecBuilder.build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(run.id),
      team_metadata: %{run_id: run.id, source: :dag},
      prompt_builder: fn agent, _builder_state ->
        Map.fetch!(prompt_by_name, agent.name)
      end,
      agent_metadata_builder: fn agent, builder_state ->
        agent_metadata(agent, builder_state, run.id)
      end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _window_name, built_session ->
        "#{built_session}-#{agent.name}"
      end
    )
  end

  @doc "Return the prompt directory path for a DAG run."
  @spec prompt_dir(String.t()) :: String.t()
  def prompt_dir(run_id), do: Path.join(prompt_root_dir(), run_id)

  @doc "Return the root prompt directory, from config or default."
  @spec prompt_root_dir() :: String.t()
  def prompt_root_dir do
    Application.get_env(:ichor, :dag_prompt_root_dir, Path.expand("~/.ichor/dag"))
  end

  # Build workshop state from the "dag" preset, then inject runtime workers.
  defp dag_state(session, worker_groups) do
    base = Presets.apply(BlueprintState.defaults(), "dag")

    # Preset has coordinator (id=1) and lead (id=2) with next_id=3.
    # Inject one worker agent per group starting at next_id.
    {injected_state, final_next_id} =
      worker_groups
      |> Enum.with_index(base.ws_next_id)
      |> Enum.reduce({base, base.ws_next_id}, fn {worker, slot_id}, {acc_state, _} ->
        agent = %{
          id: slot_id,
          name: worker.name,
          capability: "builder",
          model: "sonnet",
          permission: "default",
          persona: "DAG worker. Implements only the jobs assigned to #{worker.name}.",
          file_scope: Enum.join(worker.allowed_files, "\n"),
          quality_gates: "mix compile --warnings-as-errors",
          x: rem(slot_id - 3, 4) * 180 + 40,
          y: 400
        }

        new_links = [
          %{from: 1, to: slot_id},
          %{from: 2, to: slot_id}
        ]

        new_rules = [
          %{from: 2, to: slot_id, policy: "allow", via: nil},
          %{from: slot_id, to: 2, policy: "allow", via: nil}
        ]

        updated =
          acc_state
          |> Map.update!(:ws_agents, &(&1 ++ [agent]))
          |> Map.update!(:ws_spawn_links, &(&1 ++ new_links))
          |> Map.update!(:ws_comm_rules, &(&1 ++ new_rules))
          |> Map.put(:ws_next_id, slot_id + 1)

        {updated, slot_id + 1}
      end)

    # team_name MUST equal session for DAG cleanup semantics.
    injected_state
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_next_id, final_next_id)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp build_roster(session, worker_groups) do
    names = ["coordinator", "lead"] ++ Enum.map(worker_groups, & &1.name)

    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end

  defp build_prompt_map(shared, roster, worker_groups) do
    shared_with_roster = Map.put(shared, :roster, roster)

    worker_prompts =
      Map.new(worker_groups, fn worker ->
        ctx = Map.put(shared_with_roster, :worker, worker)
        {worker.name, DagPrompts.worker(ctx)}
      end)

    Map.merge(worker_prompts, %{
      "coordinator" => DagPrompts.coordinator(shared_with_roster),
      "lead" => DagPrompts.lead(shared_with_roster)
    })
  end

  defp agent_metadata(agent, state, run_id) do
    %{
      run_id: run_id,
      source: :dag,
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end
end
