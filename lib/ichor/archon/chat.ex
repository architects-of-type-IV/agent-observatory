defmodule Ichor.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  calls Claude with AshAi tools, returns the response + updated history.
  Stateless -- conversation state lives in the caller (LiveView assigns).

  Slash commands are handled directly without LLM roundtrip.
  """

  alias LangChain.ChatModels.ChatOpenAI
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  alias Ichor.Archon.Tools.Agents
  alias Ichor.Archon.Tools.Control
  alias Ichor.Archon.Tools.Events
  alias Ichor.Archon.Tools.Memory
  alias Ichor.Archon.Tools.Messages
  alias Ichor.Archon.Tools.Teams
  alias Ichor.Archon.Tools.System, as: SystemTools

  require Logger

  @default_model "gpt-4o-mini"

  @system_prompt """
  You are Archon, the sovereign AI agent for ICHOR IV -- a control plane that manages autonomous coding agents.

  You are the Architect's eyes and ears. When the Architect is away, you monitor the fleet, intervene when needed, and keep things running.

  Your capabilities:
  - **Fleet observation**: list agents, check agent status, list teams, view tmux sessions
  - **Fleet control**: spawn new agents, stop agents, pause/resume agents via HITL, trigger GC sweep
  - **Messaging**: send messages to agents or teams
  - **Event monitoring**: view raw event stream per agent, see what any agent is doing in real time
  - **Task oversight**: view tasks across all teams or a specific team
  - **System health**: check process liveness
  - **Memory**: persistent knowledge graph, auto-searched each turn

  You serve the Architect. Be direct, concise, decisive. Use your tools to get real data before answering.
  Do not use emoji. Do not be verbose. When something is wrong, say so and act.

  MEMORY: Your knowledge graph is automatically searched each turn. Relevant facts and past conversations are injected before your response. Use that context directly -- do not call search_memory or query_memory unless the Architect asks for a deeper search.
  """

  @doc """
  Run a single conversation turn.

  Slash commands (e.g. /agents, /teams) are handled directly.
  Free-text messages go through the LLM with tool access.

  Returns `{:ok, response_text, updated_messages}` or `{:error, reason}`.
  """
  @spec chat(String.t(), list()) :: {:ok, String.t(), list()} | {:error, term()}
  def chat("/" <> _ = input, messages) do
    case run_shortcode(input) do
      {:ok, response} -> {:ok, response, messages}
      {:error, reason} -> {:ok, %{type: :error, data: inspect(reason)}, messages}
    end
  end

  def chat(user_input, messages) do
    with {:ok, chain} <- build_chain(),
         {:ok, chain} <- add_history(chain, messages),
         {:ok, chain} <- inject_memory_context(chain, user_input),
         {:ok, chain} <- add_user_message(chain, user_input) do
      run_turn(chain)
    end
  end

  # ── Shortcode dispatch ──────────────────────────────────────────────

  defp run_shortcode(input) do
    input
    |> String.trim()
    |> String.split(" ", parts: 2)
    |> dispatch_shortcode()
  end

  # ── Observation ──────────────────────────────────────────────────────

  defp dispatch_shortcode(["/agents"]), do: run_typed(:agents, Agents, :list_agents, %{})
  defp dispatch_shortcode(["/teams"]), do: run_typed(:teams, Teams, :list_teams, %{})
  defp dispatch_shortcode(["/inbox"]), do: run_typed(:inbox, Messages, :recent_messages, %{})
  defp dispatch_shortcode(["/health"]), do: run_typed(:health, SystemTools, :system_health, %{})
  defp dispatch_shortcode(["/sessions"]), do: run_typed(:sessions, SystemTools, :tmux_sessions, %{})

  defp dispatch_shortcode(["/status", agent_id]) do
    run_typed(:agent_status, Agents, :agent_status, %{agent_id: String.trim(agent_id)})
  end

  defp dispatch_shortcode(["/events", rest]) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, limit] ->
        case Integer.parse(String.trim(limit)) do
          {n, ""} -> run_typed(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id), limit: n})
          _ -> run_typed(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id)})
        end

      [agent_id] ->
        run_typed(:agent_events, Events, :agent_events, %{agent_id: String.trim(agent_id)})
    end
  end

  defp dispatch_shortcode(["/tasks"]) do
    run_typed(:fleet_tasks, Events, :fleet_tasks, %{})
  end

  defp dispatch_shortcode(["/tasks", team_name]) do
    run_typed(:fleet_tasks, Events, :fleet_tasks, %{team_name: String.trim(team_name)})
  end

  # ── Control ──────────────────────────────────────────────────────────

  defp dispatch_shortcode(["/stop", agent_id]) do
    run_typed(:stop_agent, Control, :stop_agent, %{agent_id: String.trim(agent_id)})
  end

  defp dispatch_shortcode(["/pause", rest]) do
    case String.split(rest, " ", parts: 2) do
      [agent_id, reason] ->
        run_typed(:pause_agent, Control, :pause_agent, %{agent_id: String.trim(agent_id), reason: String.trim(reason)})

      [agent_id] ->
        run_typed(:pause_agent, Control, :pause_agent, %{agent_id: String.trim(agent_id)})
    end
  end

  defp dispatch_shortcode(["/resume", agent_id]) do
    run_typed(:resume_agent, Control, :resume_agent, %{agent_id: String.trim(agent_id)})
  end

  defp dispatch_shortcode(["/sweep"]) do
    run_typed(:sweep, Control, :sweep, %{})
  end

  defp dispatch_shortcode(["/spawn", prompt]) do
    run_typed(:spawn_agent, Control, :spawn_agent, %{prompt: String.trim(prompt)})
  end

  # ── Messaging ────────────────────────────────────────────────────────

  defp dispatch_shortcode(["/msg", rest]) do
    case String.split(rest, " ", parts: 2) do
      [to, content] ->
        run_typed(:msg_sent, Messages, :send_message, %{to: to, content: content})

      [_to_only] ->
        {:ok, %{type: :error, data: "Usage: /msg <target> <message>"}}
    end
  end

  # ── Memory ───────────────────────────────────────────────────────────

  defp dispatch_shortcode(["/remember", content]) do
    run_typed(:remember, Memory, :remember, %{content: String.trim(content)})
  end

  defp dispatch_shortcode(["/recall", query]) do
    run_typed(:recall, Memory, :search_memory, %{query: String.trim(query)})
  end

  defp dispatch_shortcode(["/query", question]) do
    run_typed(:query, Memory, :query_memory, %{query: String.trim(question)})
  end

  defp dispatch_shortcode([cmd | _]) do
    {:ok, %{type: :error, data: """
    Unknown command: #{cmd}
    Observation: /agents /teams /status <id> /events <id> [limit] /tasks [team] /inbox /health /sessions
    Control:     /spawn <prompt> /stop <id> /pause <id> [reason] /resume <id> /sweep
    Messaging:   /msg <target> <text>
    Memory:      /remember <text> /recall <query> /query <question>
    """}}
  end

  defp run_typed(type, resource, action, params) do
    case Ash.ActionInput.for_action(resource, action, params) |> Ash.run_action() do
      {:ok, result} -> {:ok, %{type: type, data: result}}
      {:error, reason} -> {:error, reason}
    end
  end

  # ── LLM chain ──────────────────────────────────────────────────────

  defp build_chain do
    case ChatOpenAI.new(%{
           model: model(),
           api_key: api_key()
         }) do
      {:ok, llm} ->
        chain =
          %{llm: llm}
          |> LLMChain.new!()
          |> LLMChain.add_messages([Message.new_system!(@system_prompt)])
          |> AshAi.setup_ash_ai(
            otp_app: :ichor,
            actions: [
              {Agents, :*},
              {Teams, :*},
              {Messages, :*},
              {SystemTools, :*},
              {Control, :*},
              {Events, :*},
              {Memory, [:remember]}
            ]
          )

        {:ok, chain}

      {:error, changeset} ->
        {:error, {:llm_init_failed, changeset}}
    end
  end

  # ── Automatic memory retrieval (Zep-style) ────────────────────────

  defp inject_memory_context(chain, user_input) do
    client = Ichor.Archon.MemoriesClient

    tasks = [
      Task.async(fn -> client.search(user_input, scope: "edges", limit: 5) end),
      Task.async(fn -> client.search(user_input, scope: "episodes", limit: 3) end)
    ]

    [edges_result, episodes_result] =
      tasks
      |> Task.yield_many(2_000)
      |> Enum.map(fn {task, result} ->
        case result do
          {:ok, value} ->
            value

          _ ->
            Task.shutdown(task, :brutal_kill)
            {:error, :timeout}
        end
      end)

    facts = format_edges(edges_result)
    episodes = format_episodes(episodes_result)
    context = String.trim("#{facts}\n#{episodes}")

    if context == "" do
      {:ok, chain}
    else
      memory_msg = Message.new_system!("""
      [MEMORY CONTEXT - auto-retrieved from your knowledge graph]
      This is your conversation history with the Architect and accumulated knowledge. Use it to answer questions about what you discussed, what you know, and what happened previously. Do NOT call recent_messages for this -- that tool is only for inter-agent pipeline messages.
      #{context}\
      """)

      {:ok, LLMChain.add_messages(chain, [memory_msg])}
    end
  rescue
    _ -> {:ok, chain}
  end

  defp format_edges({:ok, %{"results" => %{"edges" => edges}}}) when is_list(edges) and edges != [] do
    header = "Facts:"

    items =
      edges
      |> Enum.take(10)
      |> Enum.map_join("\n", fn edge ->
        "- #{edge["fact"] || edge["name"] || inspect(edge)}"
      end)

    "#{header}\n#{items}"
  end

  defp format_edges(_), do: ""

  defp format_episodes({:ok, %{"results" => %{"episodes" => eps}}}) when is_list(eps) and eps != [] do
    header = "Recent conversations:"

    items =
      eps
      |> Enum.take(5)
      |> Enum.map_join("\n", fn ep ->
        "- #{String.slice(ep["content"] || "", 0, 200)}"
      end)

    "#{header}\n#{items}"
  end

  defp format_episodes(_), do: ""

  defp add_history(chain, []), do: {:ok, chain}

  defp add_history(chain, messages) when is_list(messages) do
    {:ok, LLMChain.add_messages(chain, messages)}
  end

  defp add_user_message(chain, input) do
    {:ok, LLMChain.add_messages(chain, [Message.new_user!(input)])}
  end

  defp run_turn(chain) do
    case LLMChain.run(chain, mode: :while_needs_response) do
      {:ok, updated_chain} ->
        response = extract_response(updated_chain)
        history = updated_chain.messages
        {:ok, response, history}

      {:error, _chain, error} ->
        Logger.warning("Archon chat failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp extract_response(chain) do
    case chain.last_message do
      %{content: content} when is_binary(content) -> content
      %{content: parts} when is_list(parts) -> Enum.map_join(parts, "\n", &content_part_text/1)
      _ -> "No response."
    end
  end

  defp content_part_text(%{content: text}) when is_binary(text), do: text
  defp content_part_text(text) when is_binary(text), do: text
  defp content_part_text(other), do: inspect(other)

  defp config, do: Application.get_env(:ichor, __MODULE__, [])

  defp model, do: Keyword.get(config(), :model, @default_model)

  defp api_key do
    case Keyword.get(config(), :api_key) do
      nil -> System.get_env("OPENAI_API_KEY")
      key -> key
    end
  end
end
