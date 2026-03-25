defmodule Ichor.Workshop.TeamSpec do
  @moduledoc """
  Pure builder for `TeamSpec` and `AgentSpec` runtime contracts across all run modes.

  Consolidates MES, pipeline, and planning spec construction. Per-mode differences
  (preset name, prompt builder, metadata) are expressed as data, not separate modules.

  Public API:
    - build(:mes, run_id, team_name, opts)
    - build(:pipeline, run, session, brief, tasks, worker_groups, prompt_ctx, opts)
    - build(:planning, run_id, mode, project_id, planning_project_id, brief)
    - build_corrective(run_id, session, reason, attempt)
    - session_name(run_id) -- MES only
    - prompt_dir(:mes, run_id) | prompt_dir(:pipeline, run_id) | prompt_dir(:planning, run_id, mode)
    - prompt_root_dir(:mes) | prompt_root_dir(:pipeline) | prompt_root_dir(:planning)
  """

  alias Ichor.Factory.RunRef
  alias Ichor.Fleet.AgentSpec
  alias Ichor.Infrastructure.TeamSpec, as: Spec
  alias Ichor.Workshop.{CanvasState, PipelinePrompts, Presets, PromptProtocol, Team, TeamPrompts}

  @doc "Builds a TeamSpec for a MES run."
  @spec build(:mes, String.t(), String.t(), keyword()) :: Spec.t()
  def build(:mes, run_id, team_name, opts) do
    research_context = Keyword.get(opts, :research_context, %{})
    session = session_name(run_id)
    state = mes_state(team_name)

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:mes, run_id),
      team_metadata: %{run_id: run_id, source: :mes, team_template: mes_team_name()},
      template_vars: mes_template_vars(run_id, research_context),
      extra_contacts_builder: &PromptProtocol.extra_contacts_for/1,
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

  @doc "Builds a TeamSpec for a pipeline execution run."
  @spec build(:pipeline, map(), String.t(), String.t(), [map()], [map()], map(), keyword()) ::
          Spec.t()
  def build(:pipeline, run, session, brief, tasks, worker_groups, prompt_ctx, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module, PipelinePrompts)
    state = pipeline_state(session, worker_groups)
    worker_map = Map.new(worker_groups, &{&1.name, &1})

    shared = %{
      run_id: run.id,
      session: session,
      brief: brief,
      jobs: tasks,
      worker_groups: worker_groups,
      plugin_dir: prompt_ctx.plugin_dir,
      roster: PromptProtocol.roster_block(session, Enum.map(state.ws_agents, & &1.name))
    }

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:pipeline, run.id),
      team_metadata: %{run_id: run.id, source: :pipeline},
      prompt_builder: fn agent, _state ->
        agent_shared =
          case Map.fetch(worker_map, agent.name) do
            {:ok, worker} -> Map.put(shared, :worker, worker)
            :error -> shared
          end

        prompt_mod.for_agent(agent, agent_shared)
      end,
      agent_metadata_builder: fn agent, state -> pipeline_agent_meta(agent, state, run.id) end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _win, session -> "#{session}-#{agent.name}" end
    )
  end

  @doc "Builds a TeamSpec for a planning mode run."
  @spec build(
          :planning,
          String.t(),
          String.t(),
          String.t() | nil,
          String.t(),
          keyword()
        ) :: Spec.t()
  def build(:planning, run_id, mode, planning_project_id, brief, opts) do
    prompt_mod = Keyword.get(opts, :prompt_module)
    session = "planning-#{mode}-#{run_id}"
    state = planning_state(session, mode)

    context = %{
      run_id: run_id,
      roster: PromptProtocol.roster_block(session, Enum.map(state.ws_agents, & &1.name)),
      project_id: planning_project_id,
      brief: brief
    }

    build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(:planning, run_id, mode),
      team_metadata: %{run_id: run_id, source: :planning, mode: mode},
      prompt_builder: fn agent, _state -> prompt_mod.for_agent(mode, agent, context) end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _win, session -> "#{session}-#{agent.name}" end
    )
  end

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

  defp mes_state(team_name) do
    preset_state = Presets.apply(CanvasState.defaults(), mes_team_name())

    base =
      case Team.by_name(mes_team_name()) do
        {:ok, team} ->
          db_state = CanvasState.apply_team(CanvasState.defaults(), team)
          merge_preset_personas(db_state, preset_state)

        {:error, _} ->
          preset_state
      end

    base
    |> Map.put(:ws_team_name, team_name)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp merge_preset_personas(db_state, preset_state) do
    preset_personas = Map.new(preset_state.ws_agents, fn a -> {a.name, a.persona} end)

    updated_agents =
      Enum.map(db_state.ws_agents, fn agent ->
        # DB persona is structural (role description for Workshop canvas).
        # Preset persona is operational (full prompt template for spawning).
        Map.put(agent, :persona, Map.get(preset_personas, agent.name, agent.persona))
      end)

    # Overlay both personas AND comm_rules from preset.
    # DB comm_rules can be stale (e.g. planner->coordinator instead of planner->lead).
    db_state
    |> Map.put(:ws_agents, updated_agents)
    |> Map.put(:ws_comm_rules, preset_state.ws_comm_rules)
  end

  defp mes_team_name do
    Application.get_env(:ichor, :mes_workshop_team_name, "mes")
  end

  defp mes_template_vars(run_id, research_context) do
    %{
      "run_id" => run_id,
      "open_gaps" => Map.get(research_context, :open_gaps, ""),
      "existing_plugins" => Map.get(research_context, :existing_plugins, ""),
      "dead_zones" => Map.get(research_context, :dead_zones, ""),
      "pain_points" => Map.get(research_context, :pain_points, "")
    }
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

  defp pipeline_state(session, worker_groups) do
    {:ok, preset} = Presets.fetch("pipeline")
    base = Presets.apply(CanvasState.defaults(), "pipeline")
    base_ids = Enum.map(base.ws_agents, & &1.id)
    hub_id = preset.dispatch_hub_id

    {agents, links, rules} =
      worker_groups
      |> Enum.with_index(base.ws_next_id)
      |> Enum.reduce({[], [], []}, fn {worker, slot_id}, {acc_a, acc_l, acc_r} ->
        agent = %{
          id: slot_id,
          name: worker.name,
          capability: "builder",
          model: "sonnet",
          permission: "default",
          persona: "Pipeline worker. Implements only the tasks assigned to #{worker.name}.",
          file_scope: Enum.join(worker.allowed_files, "\n"),
          quality_gates: "mix compile --warnings-as-errors",
          x: rem(slot_id - base.ws_next_id, 4) * 180 + 40,
          y: 400
        }

        new_links = Enum.map(base_ids, fn id -> %{from: id, to: slot_id} end)

        new_rules =
          if hub_id do
            [
              %{from: hub_id, to: slot_id, policy: "allow", via: nil},
              %{from: slot_id, to: hub_id, policy: "allow", via: nil}
            ]
          else
            []
          end

        {[agent | acc_a], new_links ++ acc_l, new_rules ++ acc_r}
      end)

    last_id = base.ws_next_id + length(worker_groups)

    base
    |> Map.update!(:ws_agents, &(&1 ++ Enum.reverse(agents)))
    |> Map.update!(:ws_spawn_links, &(&1 ++ Enum.reverse(links)))
    |> Map.update!(:ws_comm_rules, &(&1 ++ Enum.reverse(rules)))
    |> Map.put(:ws_next_id, last_id)
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_cwd, File.cwd!())
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

  defp planning_state(session, mode) do
    CanvasState.defaults()
    |> Presets.apply("planning_#{mode}")
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp build_from_state(state, opts) do
    team_name = state.ws_team_name
    session = Keyword.get(opts, :session, default_session_name(team_name))
    cwd = blank_to_cwd(state.ws_cwd)
    ordered_agents = Presets.spawn_order(state.ws_agents, state.ws_spawn_links)

    prompt_builder =
      Keyword.get(opts, :prompt_builder, fn agent, _state -> agent.persona || "" end)

    extra_contacts_builder =
      Keyword.get(opts, :extra_contacts_builder, &PromptProtocol.extra_contacts_for/1)

    caller_vars = Keyword.get(opts, :template_vars, %{})
    tool_prefix = Keyword.get(opts, :tool_prefix, "")

    agent_metadata_builder = Keyword.get(opts, :agent_metadata_builder, &default_agent_metadata/2)
    window_name_builder = Keyword.get(opts, :window_name_builder, & &1.name)

    agent_id_builder =
      Keyword.get(opts, :agent_id_builder, fn _agent, built_window_name, built_session ->
        "#{built_session}-#{built_window_name}"
      end)

    critical_rules = PromptProtocol.critical_rules(tool_prefix)

    Spec.new(%{
      team_name: team_name,
      session: session,
      cwd: cwd,
      agents:
        Enum.map(ordered_agents, fn agent ->
          built_window_name = window_name_builder.(agent)
          role_prompt = prompt_builder.(agent, state)

          contacts_block =
            PromptProtocol.allowed_contacts(
              agent.id,
              state.ws_comm_rules,
              state.ws_agents,
              session,
              extra_contacts_builder.(agent)
            )

          # Caller vars first, infrastructure vars override (authoritative).
          template_vars =
            Map.merge(caller_vars, %{
              "session" => session,
              "agent_name" => agent.name,
              "agent_session_id" => "#{session}-#{agent.name}",
              "critical_rules" => critical_rules,
              "allowed_contacts" => contacts_block
            })

          prompt = PromptProtocol.render_template(role_prompt, template_vars)

          AgentSpec.new(%{
            name: agent.name,
            window_name: built_window_name,
            agent_id: agent_id_builder.(agent, built_window_name, session),
            capability: agent.capability,
            model: agent.model,
            cwd: cwd,
            team_name: team_name,
            session: session,
            prompt: prompt,
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
  defp blank_to_cwd(value), do: value

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
