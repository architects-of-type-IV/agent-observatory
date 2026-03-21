defmodule Ichor.Workshop.TeamSpec do
  @moduledoc """
  Pure builder for `TeamSpec` and `AgentSpec` runtime contracts across all run modes.

  Consolidates MES, pipeline, and planning spec construction. Per-mode differences
  (preset name, prompt builder, metadata) are expressed as data, not separate modules.

  Public API:
    - build(:mes, run_id, team_name)
    - build(:pipeline, run, session, brief, tasks, worker_groups, prompt_ctx)
    - build(:planning, run_id, mode, project_id, planning_project_id, brief)
    - build_corrective(run_id, session, reason, attempt)
    - session_name(run_id) -- MES only
    - prompt_dir(:mes, run_id) | prompt_dir(:pipeline, run_id) | prompt_dir(:planning, run_id, mode)
    - prompt_root_dir(:mes) | prompt_root_dir(:pipeline) | prompt_root_dir(:planning)
  """

  alias Ichor.Factory.RunRef
  alias Ichor.Infrastructure.AgentSpec
  alias Ichor.Infrastructure.TeamSpec, as: Spec
  alias Ichor.Workshop.{CanvasState, PipelinePrompts, Presets, Team, TeamPrompts}

  # MES

  @doc "Builds a TeamSpec for a MES run."
  @spec build(:mes, String.t(), String.t(), keyword()) :: Spec.t()
  def build(:mes, run_id, team_name, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module, TeamPrompts)
    research_context = Keyword.get(opts, :research_context, %{})
    session = session_name(run_id)
    roster = TeamPrompts.roster(session)
    state = mes_state(team_name)

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:mes, run_id),
      team_metadata: %{run_id: run_id, source: :mes, team_template: mes_team_name()},
      prompt_builder: fn agent, _state ->
        mes_prompt(prompt_mod, agent, run_id, roster, research_context)
      end,
      agent_metadata_builder: fn agent, state -> mes_agent_meta(agent, state, run_id) end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _win, session -> "#{session}-#{agent.name}" end
    )
  end

  @doc "Builds a corrective TeamSpec for a failed MES quality gate."
  @spec build_corrective(String.t(), String.t(), String.t() | nil, pos_integer(), keyword()) ::
          Spec.t()
  def build_corrective(run_id, session, reason, attempt, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module, TeamPrompts)
    cwd = File.cwd!()
    name = "corrective-#{attempt}"

    Spec.new(%{
      team_name: session_name(run_id),
      session: session,
      cwd: cwd,
      agents: [
        AgentSpec.new(%{
          name: name,
          window_name: name,
          agent_id: "#{session}-#{name}",
          capability: "builder",
          model: "sonnet",
          cwd: cwd,
          team_name: session_name(run_id),
          session: session,
          prompt: prompt_mod.corrective(run_id, session, reason),
          metadata: %{run_id: run_id}
        })
      ],
      prompt_dir: prompt_dir(:mes, run_id),
      metadata: %{run_id: run_id}
    })
  end

  @doc "Returns the tmux session name for a MES run."
  @spec session_name(String.t()) :: String.t()
  def session_name(run_id), do: RunRef.session_name(RunRef.new(:mes, run_id))

  # Pipeline

  @doc "Builds a TeamSpec for a pipeline execution run."
  @spec build(:pipeline, map(), String.t(), String.t(), [map()], [map()], map(), keyword()) ::
          Spec.t()
  def build(:pipeline, run, session, brief, tasks, worker_groups, prompt_ctx, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module, PipelinePrompts)
    state = pipeline_state(session, worker_groups)

    shared = %{
      run_id: run.id,
      session: session,
      brief: brief,
      jobs: tasks,
      worker_groups: worker_groups,
      plugin_dir: prompt_ctx.plugin_dir
    }

    roster = pipeline_roster(session, worker_groups)
    prompt_map = pipeline_prompt_map(prompt_mod, shared, roster, worker_groups)

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:pipeline, run.id),
      team_metadata: %{run_id: run.id, source: :pipeline},
      prompt_builder: fn agent, _state -> Map.fetch!(prompt_map, agent.name) end,
      agent_metadata_builder: fn agent, state -> pipeline_agent_meta(agent, state, run.id) end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _win, session -> "#{session}-#{agent.name}" end
    )
  end

  # Planning

  @doc "Builds a TeamSpec for a planning mode run."
  @spec build(
          :planning,
          String.t(),
          String.t(),
          String.t(),
          String.t() | nil,
          String.t(),
          keyword()
        ) :: Spec.t()
  def build(:planning, run_id, mode, _project_id, planning_project_id, brief, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module)
    session = "planning-#{mode}-#{run_id}"
    state = planning_state(session, mode)
    roster = planning_roster(session, mode)
    prompt_map = planning_prompt_map(prompt_mod, mode, run_id, roster, planning_project_id, brief)

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:planning, run_id, mode),
      team_metadata: %{run_id: run_id, source: :planning, mode: mode},
      prompt_builder: fn agent, _state -> Map.fetch!(prompt_map, agent.name) end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _win, session -> "#{session}-#{agent.name}" end
    )
  end

  # Prompt dirs (used by cleanup)

  @doc "Returns the prompt directory path for a run."
  @spec prompt_dir(:mes, String.t()) :: String.t()
  @spec prompt_dir(:pipeline, String.t()) :: String.t()
  def prompt_dir(:mes, run_id), do: Path.join(prompt_root_dir(:mes), run_id)
  def prompt_dir(:pipeline, run_id), do: Path.join(prompt_root_dir(:pipeline), run_id)

  @doc "Returns the prompt directory path for a planning mode run."
  @spec prompt_dir(:planning, String.t(), String.t()) :: String.t()
  def prompt_dir(:planning, run_id, mode),
    do: Path.join(prompt_root_dir(:planning), "#{mode}-#{run_id}")

  @doc "Returns the root prompt directory for the given run kind."
  @spec prompt_root_dir(:mes | :pipeline | :planning) :: String.t()
  def prompt_root_dir(:mes),
    do: Application.get_env(:ichor, :mes_prompt_root_dir, Path.expand("~/.ichor/mes"))

  def prompt_root_dir(:pipeline),
    do: Application.get_env(:ichor, :pipeline_prompt_root_dir, Path.expand("~/.ichor/pipeline"))

  def prompt_root_dir(:planning),
    do: Application.get_env(:ichor, :planning_prompt_root_dir, Path.expand("~/.ichor/planning"))

  # MES internals

  defp mes_state(team_name) do
    base =
      case Team.by_name(mes_team_name()) do
        {:ok, team} -> CanvasState.apply_team(CanvasState.defaults(), team)
        {:error, _} -> Presets.apply(CanvasState.defaults(), mes_team_name())
      end

    base
    |> Map.put(:ws_team_name, team_name)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp mes_team_name do
    Application.get_env(:ichor, :mes_workshop_team_name, "mes")
  end

  defp mes_prompt(prompt_mod, agent, run_id, roster, context) do
    case agent.name do
      "coordinator" -> prompt_mod.coordinator(run_id, roster)
      "lead" -> prompt_mod.lead(run_id, roster, context)
      "planner" -> prompt_mod.planner(run_id, roster, context)
      "researcher-1" -> prompt_mod.researcher_1(run_id, roster, context)
      "researcher-2" -> prompt_mod.researcher_2(run_id, roster, context)
      other -> "You are #{other} for MES run #{run_id}.\n\n#{roster}"
    end
  end

  defp mes_agent_meta(agent, state, run_id) do
    %{
      run_id: run_id,
      source: :mes,
      team_template: mes_team_name(),
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end

  # Pipeline internals

  defp pipeline_state(session, worker_groups) do
    base = Presets.apply(CanvasState.defaults(), "pipeline")

    injected =
      worker_groups
      |> Enum.with_index(base.ws_next_id)
      |> Enum.reduce(base, fn {worker, slot_id}, acc ->
        agent = %{
          id: slot_id,
          name: worker.name,
          capability: "builder",
          model: "sonnet",
          permission: "default",
          persona: "Pipeline worker. Implements only the tasks assigned to #{worker.name}.",
          file_scope: Enum.join(worker.allowed_files, "\n"),
          quality_gates: "mix compile --warnings-as-errors",
          x: rem(slot_id - 3, 4) * 180 + 40,
          y: 400
        }

        new_links = [%{from: 1, to: slot_id}, %{from: 2, to: slot_id}]

        new_rules = [
          %{from: 2, to: slot_id, policy: "allow", via: nil},
          %{from: slot_id, to: 2, policy: "allow", via: nil}
        ]

        acc
        |> Map.update!(:ws_agents, &(&1 ++ [agent]))
        |> Map.update!(:ws_spawn_links, &(&1 ++ new_links))
        |> Map.update!(:ws_comm_rules, &(&1 ++ new_rules))
        |> Map.put(:ws_next_id, slot_id + 1)
      end)

    injected
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp pipeline_roster(session, worker_groups) do
    names = ["coordinator", "lead"] ++ Enum.map(worker_groups, & &1.name)
    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end

  defp pipeline_prompt_map(prompt_mod, shared, roster, worker_groups) do
    shared_r = Map.put(shared, :roster, roster)

    workers =
      Map.new(worker_groups, fn worker ->
        {worker.name, prompt_mod.worker(Map.put(shared_r, :worker, worker))}
      end)

    Map.merge(workers, %{
      "coordinator" => prompt_mod.coordinator(shared_r),
      "lead" => prompt_mod.lead(shared_r)
    })
  end

  defp pipeline_agent_meta(agent, state, run_id) do
    %{
      run_id: run_id,
      source: :pipeline,
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end

  # Planning internals

  defp planning_state(session, mode) do
    CanvasState.defaults()
    |> Presets.apply("planning_#{mode}")
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp planning_roster(session, mode) do
    entries =
      mode
      |> planning_agent_names()
      |> Enum.map_join("\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{entries}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end

  defp planning_prompt_map(prompt_mod, "a", run_id, roster, project_id, brief) do
    %{
      "coordinator" => prompt_mod.mode_a_coordinator(run_id, roster, project_id, brief),
      "architect" => prompt_mod.mode_a_architect(run_id, roster, project_id, brief),
      "reviewer" => prompt_mod.mode_a_reviewer(run_id, roster, project_id, brief)
    }
  end

  defp planning_prompt_map(prompt_mod, "b", run_id, roster, project_id, brief) do
    %{
      "coordinator" => prompt_mod.mode_b_coordinator(run_id, roster, project_id, brief),
      "analyst" => prompt_mod.mode_b_analyst(run_id, roster, project_id, brief),
      "designer" => prompt_mod.mode_b_designer(run_id, roster, project_id, brief)
    }
  end

  defp planning_prompt_map(prompt_mod, "c", run_id, roster, project_id, brief) do
    %{
      "coordinator" => prompt_mod.mode_c_coordinator(run_id, roster, project_id, brief),
      "planner" => prompt_mod.mode_c_planner(run_id, roster, project_id, brief),
      "architect" => prompt_mod.mode_c_architect(run_id, roster, project_id, brief)
    }
  end

  defp planning_agent_names("a"), do: ~w(coordinator architect reviewer)
  defp planning_agent_names("b"), do: ~w(coordinator analyst designer)
  defp planning_agent_names("c"), do: ~w(coordinator planner architect)

  defp build_from_state(state, opts) do
    team_name = state.ws_team_name
    session = Keyword.get(opts, :session, default_session_name(team_name))
    cwd = blank_to_cwd(state.ws_cwd)
    ordered_agents = Presets.spawn_order(state.ws_agents, state.ws_spawn_links)

    prompt_builder =
      Keyword.get(opts, :prompt_builder, fn agent, _state -> agent.persona || "" end)

    agent_metadata_builder = Keyword.get(opts, :agent_metadata_builder, &default_agent_metadata/2)
    window_name_builder = Keyword.get(opts, :window_name_builder, & &1.name)

    agent_id_builder =
      Keyword.get(opts, :agent_id_builder, fn _agent, built_window_name, built_session ->
        "#{built_session}-#{built_window_name}"
      end)

    Spec.new(%{
      team_name: team_name,
      session: session,
      cwd: cwd,
      agents:
        Enum.map(ordered_agents, fn agent ->
          built_window_name = window_name_builder.(agent)

          AgentSpec.new(%{
            name: agent.name,
            window_name: built_window_name,
            agent_id: agent_id_builder.(agent, built_window_name, session),
            capability: agent.capability,
            model: agent.model,
            cwd: cwd,
            team_name: team_name,
            session: session,
            prompt: prompt_builder.(agent, state),
            metadata: agent_metadata_builder.(agent, state)
          })
        end),
      prompt_dir: Keyword.get(opts, :prompt_dir),
      metadata:
        Keyword.get(opts, :team_metadata, %{
          source: :workshop,
          strategy: state.ws_strategy,
          team_id: state[:ws_team_id]
        })
    })
  end

  defp default_agent_metadata(agent, state) do
    %{
      source: :workshop,
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end

  defp default_session_name(team_name), do: "workshop-#{slug(team_name)}"

  defp blank_to_cwd(""), do: File.cwd!()
  defp blank_to_cwd(nil), do: File.cwd!()
  defp blank_to_cwd(value), do: value

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
