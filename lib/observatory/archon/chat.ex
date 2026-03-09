defmodule Observatory.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  calls Claude with AshAi tools, returns the response + updated history.
  Stateless -- conversation state lives in the caller (LiveView assigns).
  """

  alias LangChain.ChatModels.ChatAnthropic
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  require Logger

  @default_model "claude-sonnet-4-20250514"

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

  Takes a user message string and a list of prior LangChain messages.
  Returns `{:ok, response_text, updated_messages}` or `{:error, reason}`.
  """
  @spec chat(String.t(), list()) :: {:ok, String.t(), list()} | {:error, term()}
  def chat(user_input, messages \\ []) do
    with {:ok, chain} <- build_chain(),
         {:ok, chain} <- add_history(chain, messages),
         {:ok, chain} <- add_user_message(chain, user_input) do
      run_turn(chain)
    end
  end

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
              {Observatory.Archon.Tools.Agents, :*},
              {Observatory.Archon.Tools.Teams, :*},
              {Observatory.Archon.Tools.Messages, :*},
              {Observatory.Archon.Tools.System, :*},
              {Observatory.Archon.Tools.Memory, :*}
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
