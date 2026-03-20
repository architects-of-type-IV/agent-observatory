defmodule Ichor.Tools.RuntimeOps do
  @moduledoc """
  Consolidated runtime operations resource for fleet management, messaging, events,
  system diagnostics, and manager signals.

  Merges: Agent.Spawn, Agent.Inbox, Archon.Control, Archon.Messages, Archon.Agents,
          Archon.Teams, Archon.Events, Archon.System, Archon.Manager.

  Tool-name aliases in the domain keep backward compatibility:
    :spawn_agent       -> spawn_agent   (agent-facing, optional args + task wrapper)
    :spawn_archon_agent -> spawn_agent  (archon-facing, same action, required args)
    :stop_agent / :stop_archon_agent -> stop_agent (single implementation)
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ash.Error.Unknown

  alias Ichor.AgentWatchdog
  alias Ichor.Archon.SignalManager
  alias Ichor.Control.Agent, as: ControlAgent
  alias Ichor.Control.Lifecycle.AgentLaunch
  alias Ichor.Control.Team, as: ControlTeam
  alias Ichor.Events.Runtime, as: EventRuntime
  alias Ichor.Gateway.Channels.Tmux
  alias Ichor.Gateway.HITLRelay
  alias Ichor.Messages.Bus, as: MessageBus
  alias Ichor.Observability.Message
  alias Ichor.ProtocolTracker
  alias Ichor.Tasks.Board

  # ---------------------------------------------------------------------------
  # Agent.Spawn actions (agent-facing)
  # ---------------------------------------------------------------------------

  actions do
    action :spawn_agent, :map do
      description("""
      Spawn a new agent in a tmux session with full fleet observability.
      The agent gets its own session, appears in the fleet panel, and can be
      messaged and traced. Use this instead of the built-in Agent tool when
      you need the spawned agent to be independently observable and controllable.
      """)

      argument :prompt, :string do
        allow_nil?(false)
        description("The task prompt to send to the agent. Be specific and complete.")
      end

      argument :capability, :string do
        allow_nil?(false)
        default("builder")

        description(
          "Agent role: builder (read+write), scout (read-only), lead (full), reviewer (read+write). Defaults to builder."
        )
      end

      argument :model, :string do
        allow_nil?(false)
        default("sonnet")
        description("Claude model: opus, sonnet, haiku. Defaults to sonnet.")
      end

      argument :name, :string do
        allow_nil?(false)
        default("")
        description("Agent name. Auto-generated if empty.")
      end

      argument :team_name, :string do
        allow_nil?(false)
        default("")

        description(
          "Team to join. Creates the team if it doesn't exist. Empty for standalone agent."
        )
      end

      argument :cwd, :string do
        allow_nil?(false)
        default("")
        description("Working directory. Defaults to the current project root if empty.")
      end

      argument :file_scope, {:array, :string} do
        allow_nil?(false)
        default([])
        description("List of file paths the agent should focus on. Empty for no restriction.")
      end

      argument :extra_instructions, :string do
        allow_nil?(false)
        default("")
        description("Additional instructions appended to the agent's overlay. Empty for none.")
      end

      run(fn input, _context ->
        args = input.arguments

        opts =
          %{capability: args[:capability] || "builder", model: args[:model] || "sonnet"}
          |> maybe_put(:name, args[:name])
          |> maybe_put(:team_name, args[:team_name])
          |> maybe_put(:cwd, args[:cwd])
          |> maybe_put(:file_scope, args[:file_scope])
          |> maybe_put(:extra_instructions, args[:extra_instructions])
          |> Map.put(:task, %{"subject" => "Agent task", "description" => args.prompt})

        case do_spawn(opts) do
          {:ok, result} ->
            {:ok,
             %{
               "status" => "spawned",
               "agent_id" => result.agent_id,
               "name" => result.name,
               "session" => result.session_name,
               "cwd" => result.cwd,
               "team" => args[:team_name],
               "model" => args[:model] || "sonnet",
               "note" =>
                 "Agent is running in tmux. Use send_message to communicate. Check fleet panel for status."
             }}

          {:error, {:session_exists, session}} ->
            {:error, "Session already exists: #{session}. Choose a different name."}

          {:error, {:cwd_not_found, path}} ->
            {:error, "Directory not found: #{path}"}

          {:error, reason} ->
            {:error, "Spawn failed: #{inspect(reason)}"}
        end
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Control: spawn_archon_agent (archon-facing spawn with required args)
    # ---------------------------------------------------------------------------

    action :spawn_archon_agent, :map do
      description(
        "Spawn a new Claude agent in a tmux session. Returns session_id, session_name, name."
      )

      argument :prompt, :string do
        allow_nil?(false)
        description("Task description / initial prompt for the agent")
      end

      argument :name, :string do
        allow_nil?(false)
        description("Human-readable name for the agent")
      end

      argument :capability, :string do
        allow_nil?(false)
        description("builder | scout | lead | reviewer (default: builder)")
      end

      argument :model, :string do
        allow_nil?(false)
        description("Claude model override (default: claude-sonnet-4-6)")
      end

      argument :team_name, :string do
        allow_nil?(false)
        description("Team to join (empty string if none)")
      end

      argument :cwd, :string do
        allow_nil?(false)
        description("Working directory (default: current project root)")
      end

      argument :extra_instructions, :string do
        allow_nil?(false)

        description(
          "Additional instructions prepended to the agent's system prompt (empty string if none)"
        )
      end

      run(fn input, _context ->
        args = input.arguments

        opts =
          %{prompt: args.prompt, capability: Map.get(args, :capability) || "builder"}
          |> maybe_put(:name, Map.get(args, :name))
          |> maybe_put(:model, Map.get(args, :model))
          |> maybe_put(:team_name, Map.get(args, :team_name))
          |> maybe_put(:cwd, Map.get(args, :cwd) || File.cwd!())
          |> maybe_put(:extra_instructions, Map.get(args, :extra_instructions))

        case do_spawn(opts) do
          {:ok, result} ->
            {:ok,
             %{
               "session_id" => result.session_id,
               "session_name" => result.session_name,
               "name" => result.name,
               "team" => result.team
             }}

          {:error, reason} ->
            {:error, Unknown.exception(errors: [inspect(reason)])}
        end
      end)
    end

    # ---------------------------------------------------------------------------
    # stop_agent — shared by both agent and archon tool aliases
    # ---------------------------------------------------------------------------

    action :stop_agent, :map do
      description(
        "Stop an agent by name or session ID. Terminates its BEAM process and tmux session."
      )

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      run(fn input, _context ->
        agent_id = input.arguments.agent_id

        case do_stop(agent_id) do
          {:ok, result} ->
            {:ok,
             %{
               "stopped" => result.stopped,
               "session" => result[:session],
               "name" => result[:name]
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Control: pause / resume / sweep
    # ---------------------------------------------------------------------------

    action :pause_agent, :map do
      description("Pause an agent via HITL. Buffers incoming messages until resumed.")

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      argument :reason, :string do
        allow_nil?(false)
        description("Reason for pausing (default: Paused by Archon)")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id
        reason = Map.get(input.arguments, :reason) || "Paused by Archon"

        case do_pause(query, reason) do
          {:ok, result} ->
            {:ok,
             %{
               "paused" => result.paused,
               "already_paused" => result[:already_paused],
               "session_id" => result[:session_id],
               "name" => result[:name],
               "reason" => result[:reason]
             }}
        end
      end)
    end

    action :resume_agent, :map do
      description("Resume a paused agent. Flushes any buffered messages in order.")

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id

        case do_resume(query) do
          {:ok, result} ->
            {:ok,
             %{
               "resumed" => result.resumed,
               "flushed_messages" => result[:flushed_messages],
               "session_id" => result[:session_id],
               "reason" => result[:reason]
             }}
        end
      end)
    end

    action :sweep, :map do
      description("Trigger an immediate GC sweep of dead agents from the registry.")

      run(fn _input, _context ->
        # Ichor.Registry auto-cleans on process death -- no explicit sweep needed.
        {:ok, %{"swept" => false, "message" => "no sweep needed"}}
      end)
    end

    # ---------------------------------------------------------------------------
    # Agent.Inbox actions
    # ---------------------------------------------------------------------------

    action :check_inbox, {:array, :map} do
      description(
        "Check for pending messages in your Ichor inbox. Returns unread messages from the dashboard or other agents."
      )

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      run(fn input, _context ->
        session_id = input.arguments.session_id

        case ControlAgent.get_unread(session_id) do
          {:ok, messages} -> {:ok, messages}
          {:error, _} -> {:ok, []}
        end
      end)
    end

    action :acknowledge_message, :map do
      description("Mark a message as read after processing it.")

      argument :session_id, :string do
        allow_nil?(false)
        description("Your agent session ID")
      end

      argument :message_id, :string do
        allow_nil?(false)
        description("The ID of the message to acknowledge")
      end

      run(fn input, _context ->
        ControlAgent.mark_read(input.arguments.session_id, input.arguments.message_id)
      end)
    end

    action :agent_send_message, :map do
      description("Send a message to another agent or back to the Ichor dashboard.")

      argument :from_session_id, :string do
        allow_nil?(false)
        description("Your agent session ID (the sender)")
      end

      argument :to_session_id, :string do
        allow_nil?(false)
        description("The recipient agent's session ID")
      end

      argument :content, :string do
        allow_nil?(false)
        description("The message content")
      end

      run(fn input, _context ->
        case MessageBus.send(%{
               from: input.arguments.from_session_id,
               to: input.arguments.to_session_id,
               content: input.arguments.content,
               type: :message,
               transport: :mcp
             }) do
          {:ok, result} ->
            {:ok,
             %{
               "status" => result.status,
               "to" => result.to,
               "delivered" => result.delivered,
               "via" => nil,
               "error" => nil
             }}

          {:error, reason} ->
            {:error, reason}
        end
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Messages actions
    # ---------------------------------------------------------------------------

    action :recent_messages, {:array, :map} do
      description(
        "Get recent inter-agent messages (operator/agent communications). NOT for conversation history -- your memory context has that."
      )

      argument :limit, :integer do
        allow_nil?(false)
        default(20)
        description("Max messages to return (default 20)")
      end

      run(fn input, _context ->
        limit = input.arguments[:limit] || 20

        messages =
          Message.recent!()
          |> Enum.take(limit)
          |> Enum.map(fn m ->
            %{
              "id" => m.id,
              "from" => m.sender_session,
              "to" => m.recipient,
              "content" => String.slice(m.content || "", 0, 500),
              "type" => m.type,
              "timestamp" => m.timestamp
            }
          end)

        {:ok, messages}
      end)
    end

    action :operator_send_message, :map do
      description("Send a message to an agent or team as the operator (Architect).")

      argument :to, :string do
        allow_nil?(false)
        description("Recipient: session ID, agent name, or team target (e.g. 'team:alpha')")
      end

      argument :content, :string do
        allow_nil?(false)
        description("Message content")
      end

      run(fn input, _context ->
        to = input.arguments.to
        content = input.arguments.content

        with {:ok, result} <- MessageBus.send(%{from: "archon", to: to, content: content}) do
          {:ok,
           %{
             "status" => result.status,
             "to" => result.to,
             "delivered" => result.delivered
           }}
        end
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Agents actions
    # ---------------------------------------------------------------------------

    action :list_live_agents, {:array, :map} do
      description(
        "List all registered agents with their status, team, role, model, and current tool."
      )

      run(fn _input, _context ->
        agents =
          ControlAgent.active!()
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

    # ---------------------------------------------------------------------------
    # Archon.Teams actions
    # ---------------------------------------------------------------------------

    action :list_teams, {:array, :map} do
      description("List all active teams with their members and health status.")

      run(fn _input, _context ->
        teams =
          ControlTeam.alive!()
          |> Enum.map(&format_team/1)

        {:ok, teams}
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Events actions
    # ---------------------------------------------------------------------------

    action :agent_events, {:array, :map} do
      description("Get recent hook events for a specific agent. Raw event stream.")

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      argument :limit, :integer do
        allow_nil?(false)
        description("Number of events to return (default: 30)")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id
        limit = Map.get(input.arguments, :limit) || 30

        agent = find_agent(query)
        sid = (agent && (agent.session_id || agent.agent_id)) || query

        events =
          EventRuntime.events_for_session(sid)
          |> Enum.take(limit)
          |> Enum.map(&format_event/1)

        {:ok, events}
      end)
    end

    action :fleet_tasks, {:array, :map} do
      description("List tasks across all teams, or for a specific team.")

      argument :team_name, :string do
        allow_nil?(false)
        description("Filter to a specific team (empty string for all teams)")
      end

      run(fn input, _context ->
        team_filter = Map.get(input.arguments, :team_name)

        teams =
          if team_filter in [nil, ""] do
            ControlTeam.alive!()
          else
            ControlTeam.alive!()
            |> Enum.filter(fn t -> t.name == team_filter end)
          end

        tasks = list_tasks_for_teams(teams)

        {:ok, tasks}
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.System actions
    # ---------------------------------------------------------------------------

    action :system_health, :map do
      description("Check Ichor system health: agents, teams, core processes.")

      run(fn _input, _context ->
        agents = ControlAgent.all!()
        teams = ControlTeam.alive!()

        {:ok,
         %{
           "agents" => length(agents),
           "active_agents" => Enum.count(agents, fn a -> a.status == :active end),
           "teams" => length(teams),
           "event_buffer" => alive?(EventRuntime),
           "heartbeat" => alive?(AgentWatchdog),
           "protocol_tracker" => alive?(ProtocolTracker)
         }}
      end)
    end

    action :tmux_sessions, {:array, :map} do
      description("List active tmux sessions and which agents are connected to them.")

      run(fn _input, _context ->
        sessions = Tmux.list_sessions()

        agents_by_tmux =
          ControlAgent.all!()
          |> Enum.filter(fn a -> a.channels[:tmux] != nil end)
          |> Enum.group_by(fn a -> a.channels[:tmux] end)

        result =
          Enum.map(sessions, fn s ->
            agents = Map.get(agents_by_tmux, s, [])

            %{
              "session" => s,
              "agents" =>
                Enum.map(agents, fn a ->
                  %{
                    "id" => a.agent_id,
                    "name" => a.short_name || a.name || a.agent_id,
                    "team" => a.team_name
                  }
                end)
            }
          end)

        {:ok, result}
      end)
    end

    # ---------------------------------------------------------------------------
    # Archon.Manager actions
    # ---------------------------------------------------------------------------

    action :manager_snapshot, :map do
      description("Condensed managerial snapshot derived from Signals.")

      run(fn _input, _context ->
        snapshot = SignalManager.snapshot()
        attention = SignalManager.attention()
        {:ok, Map.put(snapshot, "attention", attention)}
      end)
    end

    action :attention_queue, {:array, :map} do
      description("Current high-signal issues Archon should pay attention to.")

      run(fn _input, _context ->
        {:ok, SignalManager.attention()}
      end)
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp do_spawn(opts) when is_map(opts) do
    case AgentLaunch.spawn(opts) do
      {:ok, result} ->
        {:ok,
         %{
           session_id: result[:agent_id] || result[:session_name],
           session_name: result[:session_name],
           agent_id: result[:agent_id],
           name: result[:name],
           team: result[:team_name],
           cwd: result[:cwd]
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp do_stop(query) when is_binary(query) do
    case find_agent(query) do
      nil ->
        {:error, "agent not found: #{query}"}

      agent ->
        session = agent.tmux_session || agent.agent_id
        AgentLaunch.stop(session)
        {:ok, %{stopped: true, session: session, name: agent.name}}
    end
  end

  defp do_pause(query, reason) when is_binary(query) do
    case find_agent(query) do
      nil ->
        {:ok, %{paused: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = agent.session_id || agent.agent_id

        case HITLRelay.pause(sid, sid, "archon", reason) do
          :ok ->
            {:ok, %{paused: true, session_id: sid, name: agent.name}}

          {:ok, :already_paused} ->
            {:ok, %{paused: true, already_paused: true, session_id: sid}}
        end
    end
  end

  defp do_resume(query) when is_binary(query) do
    case find_agent(query) do
      nil ->
        {:ok, %{resumed: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = agent.session_id || agent.agent_id

        case HITLRelay.unpause(sid, sid, "archon") do
          {:ok, :not_paused} ->
            {:ok, %{resumed: false, reason: "agent was not paused"}}

          {:ok, flushed} ->
            {:ok, %{resumed: true, flushed_messages: flushed, session_id: sid}}
        end
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

  defp format_event(e) do
    %{
      "type" => e.hook_event_type,
      "tool" => e.tool_name,
      "at" => e.inserted_at,
      "summary" => e.summary,
      "cwd" => e.cwd
    }
  end

  defp alive?(name), do: Process.whereis(name) != nil

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp find_agent(query) when is_binary(query) do
    ControlAgent.all!()
    |> Enum.find(fn agent ->
      agent.agent_id == query or agent.session_id == query or
        agent.short_name == query or agent.name == query
    end)
  end

  defp format_team(team) do
    %{
      "name" => team.name,
      "members" =>
        Enum.map(team.members, fn member ->
          %{
            "session_id" => member[:agent_id] || member[:session_id],
            "role" => member[:role] || member[:name],
            "status" => member[:status]
          }
        end),
      "member_count" => team.member_count,
      "health" => team.health,
      "source" => team.source
    }
  end

  defp list_tasks_for_teams(teams) do
    Enum.flat_map(teams, fn team ->
      team.name
      |> Board.list_tasks()
      |> Enum.map(&Map.put(&1, "team", team.name))
    end)
  end
end
