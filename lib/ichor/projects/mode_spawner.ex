defmodule Ichor.Projects.ModeSpawner do
  @moduledoc """
  Spawns a Genesis mode team inside a tmux session.

  Each mode gets a 3-agent team with scoped MCP tools:
    - Mode A (Discover): coordinator + architect + reviewer -> produce ADRs
    - Mode B (Define):   coordinator + analyst + designer   -> produce FRDs/UCs
    - Mode C (Build):    coordinator + planner + architect   -> produce roadmap

  Delegates tmux/BEAM infrastructure to TeamLaunch.
  Delegates team spec construction to GenesisTeamSpecBuilder.
  Delegates prompt generation to ModePrompts.
  """

  alias Ichor.Control.Lifecycle.TeamLaunch
  alias Ichor.Projects
  alias Ichor.Projects.{GenesisTeamSpecBuilder, PlanRunner}
  alias Ichor.Signals

  @doc "Spawns a Genesis mode team (a/b/c) inside a new tmux session."
  @spec spawn_mode(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def spawn_mode(mode, project_id, genesis_node_id) do
    run_id = short_id()
    brief = load_project_brief(project_id)

    spec =
      GenesisTeamSpecBuilder.build_team_spec(run_id, mode, project_id, genesis_node_id, brief)

    case TeamLaunch.launch(spec) do
      {:ok, _session} ->
        start_run_process(run_id, mode, spec, genesis_node_id)

        Signals.emit(:genesis_team_ready, %{
          session: spec.session,
          mode: mode,
          project_id: project_id,
          genesis_node_id: genesis_node_id,
          agent_count: length(spec.agents)
        })

        {:ok, spec.session}

      {:error, reason} ->
        Signals.emit(:genesis_team_spawn_failed, %{
          session: spec.session,
          reason: inspect(reason)
        })

        {:error, reason}
    end
  end

  @doc "Returns an existing genesis node ID or creates one for the project."
  @spec ensure_genesis_node(String.t() | nil, map()) :: {:ok, String.t()} | {:error, term()}
  def ensure_genesis_node(nil, project) do
    case find_existing_node(project.id) do
      {:ok, node_id} -> {:ok, node_id}
      :not_found -> create_genesis_node(project)
    end
  end

  def ensure_genesis_node(node_id, _project), do: {:ok, node_id}

  @doc "Loads a formatted project brief string for injection into agent prompts."
  @spec load_project_brief(String.t()) :: String.t()
  def load_project_brief(project_id) do
    case Projects.get_project(project_id) do
      {:ok, project} ->
        """
        PROJECT BRIEF: #{project.title}
        Subsystem: #{project.subsystem}
        Description: #{project.description}
        Features: #{Enum.join(project.features || [], ", ")}
        Use Cases: #{Enum.join(project.use_cases || [], ", ")}
        Signal Interface: #{project.signal_interface}
        Signals Emitted: #{Enum.join(project.signals_emitted || [], ", ")}
        Signals Subscribed: #{Enum.join(project.signals_subscribed || [], ", ")}
        Architecture: #{project.architecture}
        Dependencies: #{Enum.join(project.dependencies || [], ", ")}
        """

      _ ->
        "PROJECT BRIEF: (not available)"
    end
  end

  defp find_existing_node(project_id) do
    case Ichor.Projects.node_by_project(project_id) do
      {:ok, [node | _]} -> {:ok, node.id}
      _ -> :not_found
    end
  end

  defp create_genesis_node(project) do
    case Ichor.Projects.create_node(%{
           title: project.title,
           description: project.description,
           brief: project.description,
           mes_project_id: project.id
         }) do
      {:ok, node} -> {:ok, node.id}
      error -> error
    end
  end

  defp start_run_process(run_id, mode, spec, node_id) do
    DynamicSupervisor.start_child(
      Ichor.Projects.PlanRunSupervisor,
      {PlanRunner, run_id: run_id, mode: mode, team_spec: spec, node_id: node_id}
    )
  end

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)
end
