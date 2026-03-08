defmodule Observatory.Archon.Tools.Agents do
  @moduledoc """
  Agent query tools for Archon.
  """
  use Ash.Resource, domain: Observatory.Archon.Tools

  alias Observatory.Gateway.AgentRegistry
  alias Observatory.Gateway.Channels.Tmux

  actions do
    action :list_agents, {:array, :map} do
      description "List all registered agents with their status, team, role, model, and current tool."

      run fn _input, _context ->
        agents =
          AgentRegistry.list_all()
          |> Enum.reject(fn a -> a[:role] == :operator end)
          |> Enum.map(&format_agent/1)

        {:ok, agents}
      end
    end

    action :agent_status, :map do
      description "Get detailed status of a specific agent by name or session ID."

      argument :agent_id, :string do
        allow_nil? false
        description "Agent name, short name, or session ID"
      end

      run fn input, _context ->
        query = input.arguments.agent_id

        case find_agent(query) do
          nil ->
            {:ok, %{"found" => false, "query" => query}}

          agent ->
            tmux_ok = case agent.channels.tmux do
              nil -> false
              target -> Tmux.available?(target)
            end

            {:ok, Map.merge(format_agent(agent), %{
              "found" => true,
              "started_at" => agent.started_at,
              "tmux" => agent.channels.tmux,
              "tmux_available" => tmux_ok
            })}
        end
      end
    end
  end

  defp format_agent(a) do
    %{
      "id" => a.id,
      "name" => a[:short_name] || a.id,
      "session_id" => a.session_id,
      "team" => a.team,
      "role" => a.role,
      "status" => a.status,
      "model" => a.model,
      "cwd" => a.cwd,
      "current_tool" => a.current_tool,
      "last_event_at" => a.last_event_at
    }
  end

  defp find_agent(query) do
    AgentRegistry.list_all()
    |> Enum.find(fn a ->
      a.id == query || a.session_id == query ||
        a[:short_name] == query || a[:name] == query
    end)
  end
end
