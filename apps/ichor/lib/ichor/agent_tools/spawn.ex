defmodule Ichor.AgentTools.Spawn do
  @moduledoc """
  MCP tool for spawning observable agents in tmux sessions with team registration.
  Agents spawned this way get their own session_id, are visible in the fleet panel,
  can receive messages, and are traceable.
  """
  use Ash.Resource, domain: Ichor.AgentTools
  import Ichor.MapHelpers, only: [maybe_put: 3]
  alias Ichor.Tools.AgentControl

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
        allow_nil?(true)

        description(
          "Agent role: builder (read+write), scout (read-only), lead (full), reviewer (read+write). Defaults to builder."
        )
      end

      argument :model, :string do
        allow_nil?(true)
        description("Claude model: opus, sonnet, haiku. Defaults to sonnet.")
      end

      argument :name, :string do
        allow_nil?(true)
        description("Agent name. Auto-generated if omitted.")
      end

      argument :team_name, :string do
        allow_nil?(true)

        description(
          "Team to join. Creates the team if it doesn't exist. Omit for standalone agent."
        )
      end

      argument :cwd, :string do
        allow_nil?(true)
        description("Working directory. Defaults to the current project root.")
      end

      argument :file_scope, {:array, :string} do
        allow_nil?(true)
        description("List of file paths the agent should focus on.")
      end

      argument :extra_instructions, :string do
        allow_nil?(true)
        description("Additional instructions appended to the agent's overlay.")
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

        case AgentControl.spawn(opts) do
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

    action :stop_agent, :map do
      description(
        "Stop a previously spawned agent. Terminates both the tmux session and BEAM process."
      )

      argument :agent_id, :string do
        allow_nil?(false)
        description("The agent_id returned from spawn_agent.")
      end

      run(fn input, _context ->
        agent_id = input.arguments.agent_id

        case AgentControl.stop(agent_id) do
          {:ok, %{stopped: true}} ->
            {:ok, %{"status" => "stopped", "agent_id" => agent_id}}

          {:ok, %{reason: reason}} ->
            {:error, "Stop failed: #{reason}"}
        end
      end)
    end
  end
end
