defmodule Ichor.Archon.Tools.Control do
  @moduledoc """
  Fleet control tools for Archon. Spawn, stop, pause, and resume agents.
  Trigger manual GC sweep.
  """
  use Ash.Resource, domain: Ichor.Archon.Tools

  alias Ash.Error.Unknown

  alias Ichor.AgentSpawner
  alias Ichor.Fleet.Lookup
  alias Ichor.Gateway.HITLRelay

  actions do
    action :spawn_agent, :map do
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
          %{
            prompt: args.prompt,
            name: Map.get(args, :name),
            capability: Map.get(args, :capability) || "builder",
            model: Map.get(args, :model),
            team_name: Map.get(args, :team_name),
            cwd: Map.get(args, :cwd) || File.cwd!(),
            extra_instructions: Map.get(args, :extra_instructions)
          }
          |> Enum.reject(fn {_k, v} -> is_nil(v) or v == "" end)
          |> Map.new()

        case AgentSpawner.spawn_agent(opts) do
          {:ok, result} ->
            {:ok,
             %{
               "session_id" => result[:agent_id] || result[:session_name],
               "session_name" => result[:session_name],
               "name" => result[:name],
               "team" => result[:team_name]
             }}

          {:error, reason} ->
            {:error, Unknown.exception(errors: [inspect(reason)])}
        end
      end)
    end

    action :stop_agent, :map do
      description(
        "Stop an agent by name or session ID. Terminates its BEAM process and tmux session."
      )

      argument :agent_id, :string do
        allow_nil?(false)
        description("Agent name, short name, or session ID")
      end

      run(fn input, _context ->
        query = input.arguments.agent_id

        case Lookup.find_agent(query) do
          nil ->
            {:ok, %{"stopped" => false, "reason" => "agent not found: #{query}"}}

          agent ->
            session = agent.tmux_session || agent.agent_id
            AgentSpawner.stop_agent(session)
            {:ok, %{"stopped" => true, "session" => session, "name" => agent.name}}
        end
      end)
    end

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

        case Lookup.find_agent(query) do
          nil ->
            {:ok, %{"paused" => false, "reason" => "agent not found: #{query}"}}

          agent ->
            sid = Lookup.agent_session_id(agent)

            case HITLRelay.pause(sid, sid, "archon", reason) do
              :ok ->
                {:ok, %{"paused" => true, "session_id" => sid, "name" => agent.name}}

              {:ok, :already_paused} ->
                {:ok, %{"paused" => true, "already_paused" => true, "session_id" => sid}}
            end
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

        case Lookup.find_agent(query) do
          nil ->
            {:ok, %{"resumed" => false, "reason" => "agent not found: #{query}"}}

          agent ->
            sid = Lookup.agent_session_id(agent)

            case HITLRelay.unpause(sid, sid, "archon") do
              {:ok, flushed} ->
                {:ok, %{"resumed" => true, "flushed_messages" => flushed, "session_id" => sid}}

              {:ok, :not_paused} ->
                {:ok, %{"resumed" => false, "reason" => "agent was not paused"}}
            end
        end
      end)
    end

    action :sweep, :map do
      description("Trigger an immediate GC sweep of dead agents from the registry.")

      run(fn _input, _context ->
        # Ichor.Registry auto-cleans on process death -- no explicit sweep needed.
        {:ok, %{"swept" => true}}
      end)
    end
  end
end
