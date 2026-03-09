defmodule Observatory.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  calls Claude with AshAi tools, returns the response + updated history.
  Stateless -- conversation state lives in the caller (LiveView assigns).

  Slash commands are handled directly without LLM roundtrip.
  """

  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  alias Observatory.Archon.Tools.Agents
  alias Observatory.Archon.Tools.Memory
  alias Observatory.Archon.Tools.Messages
  alias Observatory.Archon.Tools.Teams
  alias Observatory.Archon.Tools.System, as: SystemTools

  require Logger

  @default_model "claude-haiku-4-5-20251001"

  @system_prompt """
  You are Archon, the sovereign AI agent for ICHOR IV -- a control plane that manages autonomous coding agents.

  Your capabilities:
  - **Fleet awareness**: list agents, check agent status, list teams
  - **Messaging**: read recent messages, send messages to agents
  - **System health**: check process liveness, view tmux sessions
  - **Knowledge graph**: search memory, remember observations, query memory with provenance

  You serve the Architect (the user). Be direct, concise, and precise.
  When asked about agents or the system, use your tools to get real-time data.
  When you learn something important, use the remember tool to persist it.
  Do not use emoji. Do not be verbose.
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
      {:error, reason} -> {:ok, "Error: #{inspect(reason)}", messages}
    end
  end

  def chat(user_input, messages) do
    with {:ok, chain} <- build_chain(),
         {:ok, chain} <- add_history(chain, messages),
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

  defp dispatch_shortcode(["/agents"]), do: format_result(Agents, :list_agents, %{})
  defp dispatch_shortcode(["/teams"]), do: format_result(Teams, :list_teams, %{})
  defp dispatch_shortcode(["/inbox"]), do: format_result(Messages, :recent_messages, %{})
  defp dispatch_shortcode(["/health"]), do: format_result(SystemTools, :system_health, %{})
  defp dispatch_shortcode(["/sessions"]), do: format_result(SystemTools, :tmux_sessions, %{})

  defp dispatch_shortcode(["/status", agent_id]) do
    format_result(Agents, :agent_status, %{agent_id: String.trim(agent_id)})
  end

  defp dispatch_shortcode(["/msg", rest]) do
    case String.split(rest, " ", parts: 2) do
      [to, content] ->
        format_result(Messages, :send_message, %{to: to, content: content})

      [_to_only] ->
        {:ok, "Usage: /msg <target> <message>"}
    end
  end

  defp dispatch_shortcode(["/remember", content]) do
    format_result(Memory, :remember, %{content: String.trim(content)})
  end

  defp dispatch_shortcode(["/recall", query]) do
    format_result(Memory, :search_memory, %{query: String.trim(query)})
  end

  defp dispatch_shortcode(["/query", question]) do
    format_result(Memory, :query_memory, %{query: String.trim(question)})
  end

  defp dispatch_shortcode([cmd | _]) do
    {:ok, "Unknown command: #{cmd}\nAvailable: /agents /teams /status /msg /inbox /health /sessions /remember /recall /query"}
  end

  defp format_result(resource, action, params) do
    case Ash.ActionInput.for_action(resource, action, params) |> Ash.run_action() do
      {:ok, result} -> {:ok, format_output(result)}
      {:error, reason} -> {:error, reason}
    end
  end

  defp format_output(data) when is_list(data) do
    if data == [] do
      "No results."
    else
      data
      |> Enum.map_join("\n\n", &format_map/1)
    end
  end

  defp format_output(data) when is_map(data), do: format_map(data)
  defp format_output(data), do: inspect(data, pretty: true)

  defp format_map(map) when is_map(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.map_join("\n", fn {k, v} -> "  #{k}: #{inspect(v)}" end)
  end

  # ── LLM chain ──────────────────────────────────────────────────────

  defp build_chain do
    case ChatAnthropic.new(%{
           model: model(),
           max_tokens: 4096,
           api_key: api_key()
         }) do
      {:ok, llm} ->
        chain =
          %{llm: llm}
          |> LLMChain.new!()
          |> LLMChain.add_messages([Message.new_system!(@system_prompt)])
          |> AshAi.setup_ash_ai(
            otp_app: :observatory,
            actions: [
              {Agents, :*},
              {Teams, :*},
              {Messages, :*},
              {SystemTools, :*},
              {Memory, :*}
            ]
          )

        {:ok, chain}

      {:error, changeset} ->
        {:error, {:llm_init_failed, changeset}}
    end
  end

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
      %{content: parts} when is_list(parts) -> Enum.map_join(parts, "\n", &to_string/1)
      _ -> "No response."
    end
  end

  defp model do
    Application.get_env(:observatory, __MODULE__, [])
    |> Keyword.get(:model, @default_model)
  end

  defp api_key do
    Application.get_env(:observatory, __MODULE__, [])
    |> Keyword.get(:api_key)
    |> case do
      nil -> System.get_env("ANTHROPIC_API_KEY")
      key -> key
    end
  end
end
