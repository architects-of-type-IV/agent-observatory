defmodule Ichor.Projects.GenesisTeamSpecBuilder do
  @moduledoc """
  Pure builder for Genesis mode team `TeamSpec` and `AgentSpec` runtime contracts.

  Mirrors `Ichor.Projects.DagTeamSpecBuilder` -- reads the named genesis preset,
  overrides session-critical fields, builds prompt closures per mode, and delegates
  to `WorkshopTeamSpecBuilder.build_from_state/2` for the actual spec assembly.
  """

  alias Ichor.Control.BlueprintState
  alias Ichor.Control.Presets
  alias Ichor.Control.TeamSpecBuilder, as: WorkshopTeamSpecBuilder
  alias Ichor.Projects.ModePrompts

  @doc "Build a `TeamSpec` for a Genesis mode run from runtime context."
  @spec build_team_spec(String.t(), String.t(), String.t(), String.t() | nil, String.t()) ::
          Ichor.Control.Lifecycle.TeamSpec.t()
  def build_team_spec(run_id, mode, _project_id, genesis_node_id, brief) do
    session = "genesis-#{mode}-#{run_id}"
    state = genesis_state(session, mode)
    roster = build_roster(session, mode)
    prompt_by_name = build_prompt_map(mode, run_id, roster, genesis_node_id, brief)

    WorkshopTeamSpecBuilder.build_from_state(
      state,
      session: session,
      prompt_dir: prompt_dir(run_id, mode),
      team_metadata: %{run_id: run_id, source: :genesis, mode: mode},
      prompt_builder: fn agent, _builder_state ->
        Map.fetch!(prompt_by_name, agent.name)
      end,
      window_name_builder: & &1.name,
      agent_id_builder: fn agent, _window_name, built_session ->
        "#{built_session}-#{agent.name}"
      end
    )
  end

  @doc "Return the prompt directory path for a Genesis run."
  @spec prompt_dir(String.t(), String.t()) :: String.t()
  def prompt_dir(run_id, mode), do: Path.join(prompt_root_dir(), "#{mode}-#{run_id}")

  @doc "Return the root prompt directory, from config or default."
  @spec prompt_root_dir() :: String.t()
  def prompt_root_dir do
    Application.get_env(:ichor, :genesis_prompt_root_dir, Path.expand("~/.ichor/genesis"))
  end

  # Build workshop state from the named genesis preset with session overrides.
  defp genesis_state(session, mode) do
    preset_name = "genesis_#{mode}"

    BlueprintState.defaults()
    |> Presets.apply(preset_name)
    |> Map.put(:ws_team_name, session)
    |> Map.put(:ws_cwd, File.cwd!())
  end

  defp build_roster(session, mode) do
    names = agent_names_for_mode(mode)
    ids = Enum.map_join(names, "\n", fn name -> "  - #{name}: #{session}-#{name}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end

  defp build_prompt_map("a", run_id, roster, node_id, brief) do
    %{
      "coordinator" => ModePrompts.mode_a_coordinator(run_id, roster, node_id, brief),
      "architect" => ModePrompts.mode_a_architect(run_id, roster, node_id, brief),
      "reviewer" => ModePrompts.mode_a_reviewer(run_id, roster, node_id, brief)
    }
  end

  defp build_prompt_map("b", run_id, roster, node_id, brief) do
    %{
      "coordinator" => ModePrompts.mode_b_coordinator(run_id, roster, node_id, brief),
      "analyst" => ModePrompts.mode_b_analyst(run_id, roster, node_id, brief),
      "designer" => ModePrompts.mode_b_designer(run_id, roster, node_id, brief)
    }
  end

  defp build_prompt_map("c", run_id, roster, node_id, brief) do
    %{
      "coordinator" => ModePrompts.mode_c_coordinator(run_id, roster, node_id, brief),
      "planner" => ModePrompts.mode_c_planner(run_id, roster, node_id, brief),
      "architect" => ModePrompts.mode_c_architect(run_id, roster, node_id, brief)
    }
  end

  defp agent_names_for_mode("a"), do: ~w(coordinator architect reviewer)
  defp agent_names_for_mode("b"), do: ~w(coordinator analyst designer)
  defp agent_names_for_mode("c"), do: ~w(coordinator planner architect)
end
