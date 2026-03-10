defmodule Ichor.Archon.Tools.Agents do
  @moduledoc """
  Agent query tools for Archon. Reads from Fleet.Agent code interfaces.
  """
  use Ash.Resource, domain: Ichor.Archon.Tools

  alias Ichor.Fleet.Agent, as: FleetAgent
  alias Ichor.Gateway.Channels.Tmux

  actions do
    action :list_agents, {:array, :map} do
      description(
        "List all registered agents with their status, team, role, model, and current tool."
      )

      run(fn _input, _context ->
        agents =
          FleetAgent.active!()
          |> Enum.map(&format_agent/1)

        {:ok, agents}
      end)
    end

    action :agent_status, :map do
      description("Get detailed status of a specific agent by name or session ID.")

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id

        case find_agent(query) do
          nil ->
            {:ok, %{"found" => false, "query" => query}}

          agent ->
            tmux_target = agent.channels[:tmux] || agent.tmux_session

            tmux_ok =
              case tmux_target do
                nil -> false
                target -> Tmux.available?(target)
              end

            {:ok,
             Map.merge(format_agent(agent), %{
               "found" => true,
               "tmux" => tmux_target,
               "tmux_available" => tmux_ok
             })}
        end
      end)
    end
  end

  defp format_agent(a) do
    %{
      "id" => a.agent_id,
      "name" => a.short_name || a.name || a.agent_id,
      "session_id" => a.session_id,
      "team" => a.team_name,
      "role" => a.role,
      "status" => a.status,
      "model" => a.model,
      "cwd" => a.cwd,
      "current_tool" => a.current_tool,
      "last_event_at" => a.last_event_at
    }
  end

  defp find_agent(query) do
    FleetAgent.all!()
    |> Enum.find(fn a ->
      a.agent_id == query || a.session_id == query ||
        a.short_name == query || a.name == query
    end)
  end
end
