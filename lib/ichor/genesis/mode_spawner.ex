defmodule Ichor.Genesis.ModeSpawner do
  @moduledoc """
  Spawns a Genesis mode team inside a tmux session.

  Each mode gets a 3-agent team with scoped MCP tools:
    - Mode A (Discover): coordinator + architect + reviewer -> produce ADRs
    - Mode B (Define):   coordinator + analyst + designer   -> produce FRDs/UCs
    - Mode C (Build):    coordinator + planner + architect   -> produce roadmap

  Delegates tmux/BEAM infrastructure to ModeRunner.
  Delegates prompt generation to ModePrompts.
  """

  alias Ichor.Genesis.{ModePrompts, ModeRunner, RunProcess}
  alias Ichor.Projects
  alias Ichor.Signals

  @doc "Spawns a Genesis mode team (a/b/c) inside a new tmux session."
  @spec spawn_mode(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def spawn_mode(mode, project_id, genesis_node_id) do
    run_id = short_id()
    session = "genesis-#{mode}-#{run_id}"
    cwd = File.cwd!()
    brief = load_project_brief(project_id)

    agents = agents_for_mode(mode, run_id, session, genesis_node_id, brief)

    with :ok <- ModeRunner.write_agent_scripts(run_id, mode, agents),
         :ok <- ModeRunner.create_session_with_agent(session, cwd, run_id, mode, hd(agents)),
         :ok <- ModeRunner.create_remaining_windows(session, cwd, run_id, mode, tl(agents)) do
      Enum.each(agents, &ModeRunner.register_agent(session, &1, session, run_id, cwd))
      start_run_process(run_id, mode, session, genesis_node_id)

      Signals.emit(:genesis_team_ready, %{
        session: session,
        mode: mode,
        project_id: project_id,
        genesis_node_id: genesis_node_id,
        agent_count: length(agents)
      })

      {:ok, session}
    else
      {:error, reason} ->
        Signals.emit(:genesis_team_spawn_failed, %{session: session, reason: inspect(reason)})
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

  defp agents_for_mode("a", run_id, session, node_id, brief) do
    roster = team_roster(session, ~w(coordinator architect reviewer))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_a_coordinator(run_id, roster, node_id, brief)
      },
      %{
        name: "architect",
        capability: "builder",
        prompt: ModePrompts.mode_a_architect(run_id, roster, node_id, brief)
      },
      %{
        name: "reviewer",
        capability: "scout",
        prompt: ModePrompts.mode_a_reviewer(run_id, roster, node_id, brief)
      }
    ]
  end

  defp agents_for_mode("b", run_id, session, node_id, brief) do
    roster = team_roster(session, ~w(coordinator analyst designer))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_b_coordinator(run_id, roster, node_id, brief)
      },
      %{
        name: "analyst",
        capability: "builder",
        prompt: ModePrompts.mode_b_analyst(run_id, roster, node_id, brief)
      },
      %{
        name: "designer",
        capability: "builder",
        prompt: ModePrompts.mode_b_designer(run_id, roster, node_id, brief)
      }
    ]
  end

  defp agents_for_mode("c", run_id, session, node_id, brief) do
    roster = team_roster(session, ~w(coordinator planner architect))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_c_coordinator(run_id, roster, node_id, brief)
      },
      %{
        name: "planner",
        capability: "builder",
        prompt: ModePrompts.mode_c_planner(run_id, roster, node_id, brief)
      },
      %{
        name: "architect",
        capability: "builder",
        prompt: ModePrompts.mode_c_architect(run_id, roster, node_id, brief)
      }
    ]
  end

  defp start_run_process(run_id, mode, session, node_id) do
    DynamicSupervisor.start_child(
      Ichor.Genesis.RunSupervisor,
      {RunProcess, run_id: run_id, mode: mode, session: session, node_id: node_id}
    )
  end

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

  defp short_id, do: :crypto.strong_rand_bytes(4) |> Base.encode16(case: :lower)

  defp team_roster(session, names) do
    ids = Enum.map_join(names, "\n", fn n -> "  - #{n}: #{session}-#{n}" end)

    """
    TEAM ROSTER (use EXACT IDs with send_message/check_inbox):
    #{ids}
      - operator: operator
    Your session ID is: #{session}-YOUR_NAME
    """
  end
end
