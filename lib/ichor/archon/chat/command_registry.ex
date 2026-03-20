defmodule Ichor.Archon.Chat.CommandRegistry do
  @moduledoc """
  Maps parsed Archon slash commands to Ash actions and typed responses.
  """

  alias Ichor.Archon.CommandManifest
  alias Ichor.Tools.ArchonMemory
  alias Ichor.Tools.ProjectExecution
  alias Ichor.Tools.RuntimeOps

  @doc "Dispatch a parsed command map to its corresponding Ash action."
  @spec dispatch(map()) :: {:ok, %{type: atom(), data: term()}} | {:error, term()}
  def dispatch(%{command: "/agents"}), do: run(:agents, RuntimeOps, :list_live_agents, %{})
  def dispatch(%{command: "/teams"}), do: run(:teams, RuntimeOps, :list_teams, %{})
  def dispatch(%{command: "/inbox"}), do: run(:inbox, RuntimeOps, :recent_messages, %{})
  def dispatch(%{command: "/health"}), do: run(:health, RuntimeOps, :system_health, %{})
  def dispatch(%{command: "/sessions"}), do: run(:sessions, RuntimeOps, :tmux_sessions, %{})

  def dispatch(%{command: "/manager"}),
    do: run(:manager_snapshot, RuntimeOps, :manager_snapshot, %{})

  def dispatch(%{command: "/attention"}),
    do: run(:attention_queue, RuntimeOps, :attention_queue, %{})

  def dispatch(%{command: "/tasks", remainder: nil}),
    do: run(:fleet_tasks, RuntimeOps, :fleet_tasks, %{})

  def dispatch(%{command: "/sweep"}), do: run(:sweep, RuntimeOps, :sweep, %{})

  def dispatch(%{command: "/projects", remainder: nil}),
    do: run(:projects, ProjectExecution, :list_projects, %{})

  def dispatch(%{command: "/mes"}), do: run(:mes_status, ProjectExecution, :mes_status, %{})

  def dispatch(%{command: "/operator-inbox"}),
    do: run(:operator_inbox, ProjectExecution, :check_operator_inbox, %{})

  def dispatch(%{command: "/cleanup-mes"}),
    do: run(:cleanup_mes, ProjectExecution, :cleanup_mes, %{})

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
    run(:agent_status, RuntimeOps, :agent_status, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/events", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, limit] ->
        case Integer.parse(String.trim(limit)) do
          {n, ""} ->
            run(:agent_events, RuntimeOps, :agent_events, %{
              agent_id: String.trim(agent_id),
              limit: n
            })

          _ ->
            run(:agent_events, RuntimeOps, :agent_events, %{agent_id: String.trim(agent_id)})
        end

      [agent_id] ->
        run(:agent_events, RuntimeOps, :agent_events, %{agent_id: String.trim(agent_id)})
    end
  end

  def dispatch(%{command: "/tasks", remainder: team_name}) when is_binary(team_name) do
    run(:fleet_tasks, RuntimeOps, :fleet_tasks, %{team_name: String.trim(team_name)})
  end

  def dispatch(%{command: "/stop", remainder: agent_id}) when is_binary(agent_id) do
    run(:stop_agent, RuntimeOps, :stop_agent, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/pause", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, reason] ->
        run(:pause_agent, RuntimeOps, :pause_agent, %{
          agent_id: String.trim(agent_id),
          reason: String.trim(reason)
        })

      [agent_id] ->
        run(:pause_agent, RuntimeOps, :pause_agent, %{agent_id: String.trim(agent_id)})
    end
  end

  def dispatch(%{command: "/resume", remainder: agent_id}) when is_binary(agent_id) do
    run(:resume_agent, RuntimeOps, :resume_agent, %{agent_id: String.trim(agent_id)})
  end

  def dispatch(%{command: "/spawn", remainder: prompt}) when is_binary(prompt) do
    run(:spawn_agent, RuntimeOps, :spawn_archon_agent, %{prompt: String.trim(prompt)})
  end

  def dispatch(%{command: "/msg", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [to, content] ->
        run(:msg_sent, RuntimeOps, :operator_send_message, %{to: to, content: content})

      [_to_only] ->
        {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}
    end
  end

  def dispatch(%{command: "/projects", remainder: status}) when is_binary(status) do
    run(:projects, ProjectExecution, :list_projects, %{status: String.trim(status)})
  end

  def dispatch(%{command: "/remember", remainder: content}) when is_binary(content) do
    run(:remember, ArchonMemory, :remember, %{content: String.trim(content)})
  end

  def dispatch(%{command: "/recall", remainder: query}) when is_binary(query) do
    run(:recall, ArchonMemory, :search_memory, %{query: String.trim(query)})
  end

  def dispatch(%{command: "/query", remainder: question}) when is_binary(question) do
    run(:query, ArchonMemory, :query_memory, %{query: String.trim(question)})
  end

  def dispatch(%{command: command}) do
    {:ok, %{type: :error, data: CommandManifest.unknown_command_help(command)}}
  end

  defp run(type, resource, action, params) do
    case Ash.ActionInput.for_action(resource, action, params) |> Ash.run_action() do
      {:ok, result} -> {:ok, %{type: type, data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp usage_error(usage), do: %{type: :error, data: "Usage: #{usage}"}
end
