defmodule Ichor.Tools.Archon.Control do
  @moduledoc """
  Fleet control tools for Archon. Spawn, stop, pause, and resume agents.
  Trigger manual GC sweep.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ash.Error.Unknown

  alias Ichor.Control.Lifecycle.AgentLaunch
  alias Ichor.Control.Lookup
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

        case do_stop(query) do
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
  end

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
    case Lookup.find_agent(query) do
      nil ->
        {:error, "agent not found: #{query}"}

      agent ->
        session = agent.tmux_session || agent.agent_id
        AgentLaunch.stop(session)
        {:ok, %{stopped: true, session: session, name: agent.name}}
    end
  end

  defp do_pause(query, reason) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{paused: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = Lookup.agent_session_id(agent)

        case HITLRelay.pause(sid, sid, "archon", reason) do
          :ok ->
            {:ok, %{paused: true, session_id: sid, name: agent.name}}

          {:ok, :already_paused} ->
            {:ok, %{paused: true, already_paused: true, session_id: sid}}
        end
    end
  end

  defp do_resume(query) when is_binary(query) do
    case Lookup.find_agent(query) do
      nil ->
        {:ok, %{resumed: false, reason: "agent not found: #{query}"}}

      agent ->
        sid = Lookup.agent_session_id(agent)

        case HITLRelay.unpause(sid, sid, "archon") do
          {:ok, :not_paused} ->
            {:ok, %{resumed: false, reason: "agent was not paused"}}

          {:ok, flushed} ->
            {:ok, %{resumed: true, flushed_messages: flushed, session_id: sid}}
        end
    end
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, _key, ""), do: map
  defp maybe_put(map, _key, []), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
