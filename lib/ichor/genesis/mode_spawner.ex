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

  alias Ichor.Genesis.{ModePrompts, ModeRunner}
  alias Ichor.Genesis.Node, as: GenesisNode
  alias Ichor.Signals

  @spec spawn_mode(String.t(), String.t(), String.t() | nil) ::
          {:ok, String.t()} | {:error, term()}
  def spawn_mode(mode, project_id, genesis_node_id) do
    run_id = short_id()
    session = "genesis-#{mode}-#{run_id}"
    cwd = File.cwd!()

    agents = agents_for_mode(mode, run_id, session, genesis_node_id)

    with :ok <- ModeRunner.write_agent_scripts(run_id, mode, agents),
         :ok <- ModeRunner.create_session_with_agent(session, cwd, run_id, mode, hd(agents)),
         :ok <- ModeRunner.create_remaining_windows(session, cwd, run_id, mode, tl(agents)) do
      Enum.each(agents, &ModeRunner.register_agent(session, &1, session, run_id, cwd))

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

  @spec ensure_genesis_node(String.t() | nil, map()) :: {:ok, String.t()} | {:error, term()}
  def ensure_genesis_node(nil, project) do
    case GenesisNode.create(%{
           title: project.title,
           description: project.description,
           brief: project.description,
           mes_project_id: project.id
         }) do
      {:ok, node} -> {:ok, node.id}
      error -> error
    end
  end

  def ensure_genesis_node(node_id, _project), do: {:ok, node_id}

  # ── Agents per Mode ──────────────────────────────────────────────

  defp agents_for_mode("a", run_id, session, node_id) do
    roster = team_roster(session, ~w(coordinator architect reviewer))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_a_coordinator(run_id, roster, node_id)
      },
      %{
        name: "architect",
        capability: "builder",
        prompt: ModePrompts.mode_a_architect(run_id, roster, node_id)
      },
      %{
        name: "reviewer",
        capability: "scout",
        prompt: ModePrompts.mode_a_reviewer(run_id, roster, node_id)
      }
    ]
  end

  defp agents_for_mode("b", run_id, session, node_id) do
    roster = team_roster(session, ~w(coordinator analyst designer))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_b_coordinator(run_id, roster, node_id)
      },
      %{
        name: "analyst",
        capability: "builder",
        prompt: ModePrompts.mode_b_analyst(run_id, roster, node_id)
      },
      %{
        name: "designer",
        capability: "builder",
        prompt: ModePrompts.mode_b_designer(run_id, roster, node_id)
      }
    ]
  end

  defp agents_for_mode("c", run_id, session, node_id) do
    roster = team_roster(session, ~w(coordinator planner architect))

    [
      %{
        name: "coordinator",
        capability: "coordinator",
        prompt: ModePrompts.mode_c_coordinator(run_id, roster, node_id)
      },
      %{
        name: "planner",
        capability: "builder",
        prompt: ModePrompts.mode_c_planner(run_id, roster, node_id)
      },
      %{
        name: "architect",
        capability: "builder",
        prompt: ModePrompts.mode_c_architect(run_id, roster, node_id)
      }
    ]
  end

  # ── Helpers ──────────────────────────────────────────────────────

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
