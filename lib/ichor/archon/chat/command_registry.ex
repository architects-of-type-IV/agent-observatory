defmodule Ichor.Archon.Chat.CommandRegistry do
  @moduledoc """
  Maps parsed Archon slash commands to Ash actions and typed responses.
  """

  alias Ichor.Archon.Chat.ActionRunner
  alias Ichor.Archon.Tools.Agents
  alias Ichor.Archon.Tools.Control
  alias Ichor.Archon.Tools.Events
  alias Ichor.Archon.Tools.Memory
  alias Ichor.Archon.Tools.Mes
  alias Ichor.Archon.Tools.Messages
  alias Ichor.Archon.Tools.System, as: SystemTools
  alias Ichor.Archon.Tools.Teams

  @usage """
  Unknown command: %s
  Observation: /agents /teams /status <id> /events <id> [limit] /tasks [team] /inbox /health /sessions
  Control:     /spawn <prompt> /stop <id> /pause <id> [reason] /resume <id> /sweep
  Messaging:   /msg <target> <text>
  MES:         /mes /projects [status] /operator-inbox /cleanup-mes
  Memory:      /remember <text> /recall <query> /query <question>
  """

  @spec dispatch(map()) :: {:ok, %{type: atom(), data: term()}} | {:error, term()}
  def dispatch(%{command: "/agents"}), do: run(:agents, Agents, :list_agents, %{})
  def dispatch(%{command: "/teams"}), do: run(:teams, Teams, :list_teams, %{})
  def dispatch(%{command: "/inbox"}), do: run(:inbox, Messages, :recent_messages, %{})
  def dispatch(%{command: "/health"}), do: run(:health, SystemTools, :system_health, %{})
  def dispatch(%{command: "/sessions"}), do: run(:sessions, SystemTools, :tmux_sessions, %{})

  def dispatch(%{command: "/tasks", remainder: nil}),
    do: run(:fleet_tasks, Events, :fleet_tasks, %{})

  def dispatch(%{command: "/sweep"}), do: run(:sweep, Control, :sweep, %{})

  def dispatch(%{command: "/projects", remainder: nil}),
    do: run(:projects, Mes, :list_projects, %{})

  def dispatch(%{command: "/mes"}), do: run(:mes_status, Mes, :mes_status, %{})

  def dispatch(%{command: "/operator-inbox"}),
    do: run(:operator_inbox, Mes, :check_operator_inbox, %{})

  def dispatch(%{command: "/cleanup-mes"}), do: run(:cleanup_mes, Mes, :cleanup_mes, %{})

  def dispatch(%{command: "/msg", remainder: nil}),
    do: {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}

  def dispatch(%{command: "/status", remainder: nil}), do: {:ok, usage_error("/status <id>")}

  def dispatch(%{command: "/events", remainder: nil}),
    do: {:ok, usage_error("/events <id> [limit]")}

  def dispatch(%{command: "/stop", remainder: nil}), do: {:ok, usage_error("/stop <id>")}

  def dispatch(%{command: "/pause", remainder: nil}),
    do: {:ok, usage_error("/pause <id> [reason]")}

  def dispatch(%{command: "/resume", remainder: nil}), do: {:ok, usage_error("/resume <id>")}
  def dispatch(%{command: "/spawn", remainder: nil}), do: {:ok, usage_error("/spawn <prompt>")}

  def dispatch(%{command: "/remember", remainder: nil}),
    do: {:ok, usage_error("/remember <text>")}

  def dispatch(%{command: "/recall", remainder: nil}), do: {:ok, usage_error("/recall <query>")}
  def dispatch(%{command: "/query", remainder: nil}), do: {:ok, usage_error("/query <question>")}

  def dispatch(%{command: "/status", remainder: agent_id}) when is_binary(agent_id) do
    run(:agent_status, Agents, :agent_status, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/events", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, limit] ->
        case Integer.parse(String.trim(limit)) do
          {n, ""} ->
            run(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id), limit: n})

          _ ->
            run(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id)})
        end

      [agent_id] ->
        run(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id)})
    end
  end

  def dispatch(%{command: "/tasks", remainder: team_name}) when is_binary(team_name) do
    run(:fleet_tasks, Events, :fleet_tasks, %{team_name: String.trim(team_name)})
  end

  def dispatch(%{command: "/stop", remainder: agent_id}) when is_binary(agent_id) do
    run(:stop_agent, Control, :stop_agent, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/pause", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, reason] ->
        run(:pause_agent, Control, :pause_agent, %{
          agent_id: String.trim(agent_id),
          reason: String.trim(reason)
        })

      [agent_id] ->
        run(:pause_agent, Control, :pause_agent, %{agent_id: String.trim(agent_id)})
    end
  end

  def dispatch(%{command: "/resume", remainder: agent_id}) when is_binary(agent_id) do
    run(:resume_agent, Control, :resume_agent, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/spawn", remainder: prompt}) when is_binary(prompt) do
    run(:spawn_agent, Control, :spawn_agent, %{prompt: String.trim(prompt)})
  end

  def dispatch(%{command: "/msg", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [to, content] ->
        run(:msg_sent, Messages, :send_message, %{to: to, content: content})

      [_to_only] ->
        {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}
    end
  end

  def dispatch(%{command: "/projects", remainder: status}) when is_binary(status) do
    run(:projects, Mes, :list_projects, %{status: String.trim(status)})
  end

  def dispatch(%{command: "/remember", remainder: content}) when is_binary(content) do
    run(:remember, Memory, :remember, %{content: String.trim(content)})
  end

  def dispatch(%{command: "/recall", remainder: query}) when is_binary(query) do
    run(:recall, Memory, :search_memory, %{query: String.trim(query)})
  end

  def dispatch(%{command: "/query", remainder: question}) when is_binary(question) do
    run(:query, Memory, :query_memory, %{query: String.trim(question)})
  end

  def dispatch(%{command: command}) do
    {:ok, %{type: :error, data: String.replace(@usage, "%s", command)}}
  end

  defp run(type, resource, action, params) do
    action_runner().run(type, resource, action, params)
  end

  defp usage_error(usage), do: %{type: :error, data: "Usage: #{usage}"}

  defp action_runner do
    Application.get_env(:ichor, :archon_chat_action_runner_module, ActionRunner)
  end
end
