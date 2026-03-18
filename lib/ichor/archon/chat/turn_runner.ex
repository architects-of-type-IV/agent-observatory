defmodule Ichor.Archon.Chat.TurnRunner do
  @moduledoc """
  Executes a single Archon LLM-backed turn over a prepared chain.
  """

  alias Ichor.Archon.Chat.ContextBuilder
  alias Ichor.Archon.Chat.ResponseFormatter
  alias LangChain.Chains.LLMChain
  alias LangChain.Message

  require Logger

  @spec run(term(), list(), String.t()) :: {:ok, String.t(), list()} | {:error, term()}
  def run(chain, history, user_input) do
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
    case context_builder_module().build_messages(user_input) do
      {:ok, []} -> {:ok, chain}
      {:ok, messages} -> {:ok, LLMChain.add_messages(chain, messages)}
      {:error, _reason} -> {:ok, chain}
    end
  end

  defp add_user_message(chain, input) do
    {:ok, LLMChain.add_messages(chain, [Message.new_user!(input)])}
  end

  defp execute_turn(chain) do
    case llm_chain_module().run(chain, mode: :while_needs_response) do
      {:ok, updated_chain} ->
        {:ok, response_formatter_module().extract(updated_chain), updated_chain.messages}

      {:error, _chain, error} ->
        Logger.warning("Archon chat failed: #{inspect(error)}")
        {:error, error}
    end
  end

  defp context_builder_module do
    Application.get_env(:ichor, :archon_chat_context_builder_module, ContextBuilder)
  end

  defp response_formatter_module do
    Application.get_env(:ichor, :archon_chat_response_formatter_module, ResponseFormatter)
  end

  defp llm_chain_module do
    Application.get_env(:ichor, :archon_chat_llm_chain_module, LLMChain)
  end
end
