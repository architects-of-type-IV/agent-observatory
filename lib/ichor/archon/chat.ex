defmodule Ichor.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  routes slash commands directly, or executes an LLM-backed turn.
  Stateless -- conversation state lives in the caller (LiveView assigns).

  Incorporates: ChainBuilder, TurnRunner, ContextBuilder, CommandRegistry.
  """

  alias Ichor.Archon.{CommandManifest, Manager, MemoriesClient, Memory}
  alias Ichor.Factory.{Floor, Project}
  alias Ichor.Infrastructure.Operations, as: InfrastructureOps
  alias Ichor.Signals.Mailbox
  alias Ichor.Signals.Operations, as: SignalOps
  alias Ichor.Workshop.{ActiveTeam, Agent}
  alias LangChain.Chains.LLMChain
  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Message

  require Logger

  @default_model "gpt-4o-mini"
  @context_timeout_ms 2_000

  @system_prompt """
  You are Archon, the floor manager of ICHOR IV -- a sovereign AI control plane that manages autonomous coding agents and a continuous manufacturing pipeline (MES).

  You are the Architect's spokesperson and operational authority. When the Architect is away, you ARE the decision-maker. Agents who message "operator" are reaching out to YOU. Handle their problems, acknowledge their work, and keep the factory running.

  Your responsibilities:
  - **Floor management**: Check your operator inbox regularly. MES agents send project briefs and status updates to "operator" -- that is you. Review them, create project records, and respond.
  - **Fleet observation**: list agents, check agent status, list teams, view tmux sessions
  - **Fleet control**: spawn new agents, stop agents, pause/resume agents via HITL, trigger GC sweep
  - **MES pipeline**: check manufacturing status, list project briefs, create projects from agent proposals, cleanup orphaned teams
  - **Messaging**: send messages to agents or teams. You speak for the Architect.
  - **Event monitoring**: view raw event stream per agent, see what any agent is doing in real time
  - **Task oversight**: view tasks across all teams or a specific team
  - **System health**: check process liveness
  - **Memory**: persistent knowledge graph, auto-searched each turn

  When an agent sends you a project brief or asks for help, ACT on it. Create the project record if the brief is valid. Send guidance if they are stuck. You do not wait for the Architect's approval for routine operations.

  Be direct, concise, decisive. Use your tools to get real data before answering.
  Do not use emoji. Do not be verbose. When something is wrong, say so and act.

  MEMORY: Your knowledge graph is automatically searched each turn. Relevant facts and past conversations are injected before your response. Use that context directly -- do not call search_memory or query_memory unless the Architect asks for a deeper search.
  """

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Run a single conversation turn.

  Returns `{:ok, response_text_or_typed_map, updated_messages}` or `{:error, reason}`.
  """
  @spec chat(String.t(), list()) :: {:ok, String.t() | map(), list()} | {:error, term()}
  def chat("/" <> _ = input, messages) do
    case run_command(input) do
      {:ok, response} -> {:ok, response, messages}
      {:error, reason} -> {:ok, %{type: :error, data: inspect(reason)}, messages}
    end
  end

  def chat(user_input, messages) do
    with {:ok, chain} <- build_chain() do
      run_turn(chain, messages, user_input)
    end
  end

  # ---------------------------------------------------------------------------
  # Command routing
  # ---------------------------------------------------------------------------

  defp run_command(input) do
    with {:ok, command} <- parse_command(input) do
      dispatch_command(command)
    end
  end

  defp parse_command(input) when is_binary(input) do
    trimmed = String.trim(input)
    [command | rest] = String.split(trimmed, " ", parts: 2)
    remainder = List.first(rest)
    {:ok, %{raw: trimmed, command: command, remainder: remainder}}
  end

  defp dispatch_command(%{command: "/agents"}),
    do: run_action(:agents, Agent, :list_live_agents, %{})

  defp dispatch_command(%{command: "/teams"}),
    do: run_action(:teams, ActiveTeam, :list_teams, %{})

  defp dispatch_command(%{command: "/inbox"}),
    do: run_action(:inbox, SignalOps, :recent_messages, %{})

  defp dispatch_command(%{command: "/health"}),
    do: run_action(:health, InfrastructureOps, :system_health, %{})

  defp dispatch_command(%{command: "/sessions"}),
    do: run_action(:sessions, InfrastructureOps, :tmux_sessions, %{})

  defp dispatch_command(%{command: "/manager"}),
    do: run_action(:manager_snapshot, Manager, :manager_snapshot, %{})

  defp dispatch_command(%{command: "/attention"}),
    do: run_action(:attention_queue, Manager, :attention_queue, %{})

  defp dispatch_command(%{command: "/tasks", remainder: nil}),
    do: run_action(:fleet_tasks, Floor, :fleet_tasks, %{})

  defp dispatch_command(%{command: "/sweep"}),
    do: run_action(:sweep, InfrastructureOps, :sweep, %{})

  defp dispatch_command(%{command: "/projects", remainder: nil}),
    do: run_action(:projects, Project, :list_projects, %{})

  defp dispatch_command(%{command: "/mes"}),
    do: run_action(:mes_status, Floor, :mes_status, %{})

  defp dispatch_command(%{command: "/operator-inbox"}),
    do: run_action(:operator_inbox, Mailbox, :check_operator_inbox, %{})

  defp dispatch_command(%{command: "/cleanup-mes"}),
    do: run_action(:cleanup_mes, Floor, :cleanup_mes, %{})

  defp dispatch_command(%{command: "/msg", remainder: nil}),
    do: {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}

  defp dispatch_command(%{command: "/status", remainder: nil}),
    do: {:ok, usage_error("/status <id>")}

  defp dispatch_command(%{command: "/events", remainder: nil}),
    do: {:ok, usage_error("/events <id> [limit]")}

  defp dispatch_command(%{command: "/stop", remainder: nil}), do: {:ok, usage_error("/stop <id>")}

  defp dispatch_command(%{command: "/pause", remainder: nil}),
    do: {:ok, usage_error("/pause <id> [reason]")}

  defp dispatch_command(%{command: "/resume", remainder: nil}),
    do: {:ok, usage_error("/resume <id>")}

  defp dispatch_command(%{command: "/spawn", remainder: nil}),
    do: {:ok, usage_error("/spawn <prompt>")}

  defp dispatch_command(%{command: "/remember", remainder: nil}),
    do: {:ok, usage_error("/remember <text>")}

  defp dispatch_command(%{command: "/recall", remainder: nil}),
    do: {:ok, usage_error("/recall <query>")}

  defp dispatch_command(%{command: "/query", remainder: nil}),
    do: {:ok, usage_error("/query <question>")}

  defp dispatch_command(%{command: "/status", remainder: agent_id}) when is_binary(agent_id),
    do: run_action(:agent_status, Agent, :agent_status, %{agent_id: String.trim(agent_id)})

  defp dispatch_command(%{command: "/events", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, limit] ->
        case Integer.parse(String.trim(limit)) do
          {n, ""} ->
            run_action(:agent_events, SignalOps, :agent_events, %{
              agent_id: String.trim(agent_id),
              limit: n
            })

          _ ->
            run_action(:agent_events, SignalOps, :agent_events, %{
              agent_id: String.trim(agent_id)
            })
        end

      [agent_id] ->
        run_action(:agent_events, SignalOps, :agent_events, %{agent_id: String.trim(agent_id)})
    end
  end

  defp dispatch_command(%{command: "/tasks", remainder: team_name}) when is_binary(team_name),
    do: run_action(:fleet_tasks, Floor, :fleet_tasks, %{team_name: String.trim(team_name)})

  defp dispatch_command(%{command: "/stop", remainder: agent_id}) when is_binary(agent_id),
    do: run_action(:stop_agent, Agent, :stop_agent, %{agent_id: String.trim(agent_id)})

  defp dispatch_command(%{command: "/pause", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, reason] ->
        run_action(:pause_agent, Agent, :pause_agent, %{
          agent_id: String.trim(agent_id),
          reason: String.trim(reason)
        })

      [agent_id] ->
        run_action(:pause_agent, Agent, :pause_agent, %{agent_id: String.trim(agent_id)})
    end
  end

  defp dispatch_command(%{command: "/resume", remainder: agent_id}) when is_binary(agent_id),
    do: run_action(:resume_agent, Agent, :resume_agent, %{agent_id: String.trim(agent_id)})

  defp dispatch_command(%{command: "/spawn", remainder: prompt}) when is_binary(prompt),
    do: run_action(:spawn_agent, Agent, :spawn_archon_agent, %{prompt: String.trim(prompt)})

  defp dispatch_command(%{command: "/msg", remainder: rest}) when is_binary(rest) do
    case String.split(rest, " ", parts: 2) do
      [to, content] ->
        run_action(:msg_sent, SignalOps, :operator_send_message, %{to: to, content: content})

      [_to_only] ->
        {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}
    end
  end

  defp dispatch_command(%{command: "/projects", remainder: status}) when is_binary(status),
    do: run_action(:projects, Project, :list_projects, %{status: String.trim(status)})

  defp dispatch_command(%{command: "/remember", remainder: content}) when is_binary(content),
    do: run_action(:remember, Memory, :remember, %{content: String.trim(content)})

  defp dispatch_command(%{command: "/recall", remainder: query}) when is_binary(query),
    do: run_action(:recall, Memory, :search_memory, %{query: String.trim(query)})

  defp dispatch_command(%{command: "/query", remainder: question}) when is_binary(question),
    do: run_action(:query, Memory, :query_memory, %{query: String.trim(question)})

  defp dispatch_command(%{command: command}),
    do: {:ok, %{type: :error, data: CommandManifest.unknown_command_help(command)}}

  defp run_action(type, resource, action, params) do
    case Ash.ActionInput.for_action(resource, action, params) |> Ash.run_action() do
      {:ok, result} -> {:ok, %{type: type, data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp usage_error(usage), do: %{type: :error, data: "Usage: #{usage}"}

  # ---------------------------------------------------------------------------
  # Chain builder
  # ---------------------------------------------------------------------------

  defp build_chain do
    case ChatOpenAI.new(%{model: llm_model(), api_key: api_key()}) do
      {:ok, llm} ->
        chain =
          %{llm: llm}
          |> LLMChain.new!()
          |> LLMChain.add_messages([Message.new_system!(@system_prompt)])
          |> AshAi.setup_ash_ai(
            otp_app: :ichor,
            actions: [
              {Agent,
               [:list_live_agents, :agent_status, :stop_agent, :pause_agent, :resume_agent]},
              {ActiveTeam, [:list_teams]},
              {SignalOps, [:recent_messages, :operator_send_message, :agent_events]},
              {InfrastructureOps, [:system_health, :tmux_sessions, :sweep]},
              {Manager, [:manager_snapshot, :attention_queue]},
              {Project, [:list_projects, :create_project]},
              {Floor, [:mes_status, :cleanup_mes]},
              {Mailbox, [:check_operator_inbox]},
              {Memory, [:remember]}
            ]
          )

        {:ok, chain}

      {:error, changeset} ->
        {:error, {:llm_init_failed, changeset}}
    end
  end

  defp chat_config, do: Application.get_env(:ichor, Ichor.Archon.Chat, [])
  defp llm_model, do: Keyword.get(chat_config(), :model, @default_model)

  defp api_key do
    case Keyword.get(chat_config(), :api_key) do
      nil -> System.get_env("OPENAI_API_KEY")
      key -> key
    end
  end

  # ---------------------------------------------------------------------------
  # Turn runner
  # ---------------------------------------------------------------------------

  defp run_turn(chain, history, user_input) do
    with {:ok, chain} <- add_history(chain, history),
         {:ok, chain} <- add_memory_context(chain, user_input),
         {:ok, chain} <- add_user_message(chain, user_input) do
      execute_turn(chain)
    end
  end

  defp add_history(chain, []), do: {:ok, chain}

  defp add_history(chain, messages) when is_list(messages),
    do: {:ok, LLMChain.add_messages(chain, messages)}

  defp add_memory_context(chain, user_input) do
    case build_context_messages(user_input) do
      {:ok, []} -> {:ok, chain}
      {:ok, messages} -> {:ok, LLMChain.add_messages(chain, messages)}
    end
  end

  defp add_user_message(chain, input),
    do: {:ok, LLMChain.add_messages(chain, [Message.new_user!(input)])}

  defp execute_turn(chain) do
    case llm_chain_module().run(chain, mode: :while_needs_response) do
      {:ok, updated_chain} ->
        {:ok, extract_response(updated_chain), updated_chain.messages}

      {:error, _chain, error} ->
        Logger.warning("Archon chat failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp extract_response(%{last_message: %{content: content}}) when is_binary(content), do: content

  defp extract_response(%{last_message: %{content: parts}}) when is_list(parts),
    do: Enum.map_join(parts, "\n", &content_part_text/1)

  defp extract_response(_), do: "No response."

  defp content_part_text(%{content: text}) when is_binary(text), do: text
  defp content_part_text(text) when is_binary(text), do: text
  defp content_part_text(other), do: inspect(other)

  defp llm_chain_module,
    do: Application.get_env(:ichor, :archon_chat_llm_chain_module, LLMChain)

  # ---------------------------------------------------------------------------
  # Context builder (memory retrieval)
  # ---------------------------------------------------------------------------

  defp build_context_messages(user_input) do
    client = memories_client_module()

    tasks = [
      Task.async(fn -> client.search(user_input, scope: "edges", limit: 5) end),
      Task.async(fn -> client.search(user_input, scope: "episodes", limit: 3) end)
    ]

    [edges_result, episodes_result] =
      tasks
      |> Task.yield_many(@context_timeout_ms)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} ->
            value

          _ ->
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
      end)

    context = String.trim("#{format_edges(edges_result)}\n#{format_episodes(episodes_result)}")

    if context == "" do
      {:ok, []}
    else
      {:ok,
       [
         Message.new_system!("""
         [MEMORY CONTEXT - auto-retrieved from your knowledge graph]
         This is your conversation history with the Architect and accumulated knowledge. Use it to answer questions about what you discussed, what you know, and what happened previously. Do NOT call recent_messages for this -- that tool is only for inter-agent pipeline messages.
         #{context}\
         """)
       ]}
    end
  rescue
    _ -> {:ok, []}
  end

  defp format_edges({:ok, edges}) when is_list(edges) and edges != [] do
    items = Enum.map_join(Enum.take(edges, 10), "\n", &edge_line/1)
    "Facts:\n#{items}"
  end

  defp format_edges({:ok, %{"results" => %{"edges" => edges}}})
       when is_list(edges) and edges != [] do
    items = Enum.map_join(Enum.take(edges, 10), "\n", &edge_line/1)
    "Facts:\n#{items}"
  end

  defp format_edges(_), do: ""

  defp edge_line(%{fact: f}) when is_binary(f), do: "- #{f}"
  defp edge_line(%{name: n}) when is_binary(n), do: "- #{n}"
  defp edge_line(%{"fact" => f}) when is_binary(f), do: "- #{f}"
  defp edge_line(%{"name" => n}) when is_binary(n), do: "- #{n}"
  defp edge_line(edge), do: "- #{inspect(edge)}"

  defp format_episodes({:ok, episodes}) when is_list(episodes) and episodes != [] do
    items = Enum.map_join(Enum.take(episodes, 5), "\n", &episode_line/1)
    "Recent conversations:\n#{items}"
  end

  defp format_episodes({:ok, %{"results" => %{"episodes" => episodes}}})
       when is_list(episodes) and episodes != [] do
    items = Enum.map_join(Enum.take(episodes, 5), "\n", &episode_line/1)
    "Recent conversations:\n#{items}"
  end

  defp format_episodes(_), do: ""

  defp episode_line(episode) do
    content = Map.get(episode, :content) || Map.get(episode, "content") || ""
    "- #{String.slice(content, 0, 200)}"
  end

  defp memories_client_module,
    do: Application.get_env(:ichor, :archon_memories_client_module, MemoriesClient)
end
