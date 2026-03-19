defmodule Ichor.Mes.TeamSpecBuilder do
  @moduledoc """
  Pure builder for MES `TeamSpec` and `AgentSpec` runtime contracts.
  """

  alias Ichor.Control
  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.Lifecycle.TeamSpec
  alias Ichor.Mes.TeamPrompts
  alias Ichor.Workshop.BlueprintState
  alias Ichor.Workshop.Presets, as: WorkshopPresets
  alias Ichor.Workshop.TeamSpecBuilder, as: WorkshopTeamSpecBuilder

  @spec build_team_spec(String.t(), String.t()) :: TeamSpec.t()
  def build_team_spec(run_id, team_name) do
    session = session_name(run_id)
    roster = TeamPrompts.roster(session)
    state = blueprint_state(team_name)

    WorkshopTeamSpecBuilder.build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(run_id),
      team_metadata: %{run_id: run_id, source: :mes, blueprint: blueprint_name()},
      prompt_builder: fn agent, _builder_state -> prompt_for_agent(agent, run_id, roster) end,
      agent_metadata_builder: fn agent, builder_state ->
        agent_metadata(agent, builder_state, run_id)
      end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _window_name, built_session ->
        "#{built_session}-#{agent.name}"
      end
    )
  end

  @spec build_corrective_team_spec(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          TeamSpec.t()
  def build_corrective_team_spec(run_id, session, reason, attempt) do
    cwd = project_root()
    name = "corrective-#{attempt}"

    TeamSpec.new(%{
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
          prompt: TeamPrompts.corrective(run_id, session, reason),
          metadata: %{run_id: run_id}
        })
      ],
      prompt_dir: prompt_dir(run_id),
      metadata: %{run_id: run_id}
    })
  end

  @spec session_name(String.t()) :: String.t()
  def session_name(run_id), do: "mes-#{run_id}"

  @spec prompt_dir(String.t()) :: String.t()
  def prompt_dir(run_id), do: Path.join(prompt_root_dir(), run_id)

  @spec prompt_root_dir() :: String.t()
  def prompt_root_dir do
    Application.get_env(:ichor, :mes_prompt_root_dir, Path.expand("~/.ichor/mes"))
  end

  defp project_root, do: File.cwd!()

  defp blueprint_state(team_name) do
    case Control.blueprint_by_name(blueprint_name()) do
      {:ok, blueprint} ->
        BlueprintState.apply_blueprint(BlueprintState.defaults(), blueprint)
        |> Map.put(:ws_team_name, team_name)
        |> Map.put(:ws_cwd, project_root())

      {:error, _} ->
        WorkshopPresets.apply(BlueprintState.defaults(), blueprint_name())
        |> Map.put(:ws_team_name, team_name)
        |> Map.put(:ws_cwd, project_root())
    end
  end

  defp blueprint_name do
    Application.get_env(:ichor, :mes_workshop_blueprint_name, "mes")
  end

  defp prompt_for_agent(agent, run_id, roster) do
    case agent.name do
      "coordinator" -> TeamPrompts.coordinator(run_id, roster)
      "lead" -> TeamPrompts.lead(run_id, roster)
      "planner" -> TeamPrompts.planner(run_id, roster)
      "researcher-1" -> TeamPrompts.researcher_1(run_id, roster)
      "researcher-2" -> TeamPrompts.researcher_2(run_id, roster)
      other -> "You are #{other} for MES run #{run_id}.\n\n#{roster}"
    end
  end

  defp agent_metadata(agent, state, run_id) do
    %{
      run_id: run_id,
      source: :mes,
      blueprint: blueprint_name(),
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end
end
