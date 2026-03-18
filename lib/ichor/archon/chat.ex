defmodule Ichor.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  routes slash commands directly, or executes an LLM-backed turn.
  Stateless -- conversation state lives in the caller (LiveView assigns).
  """

  alias Ichor.Archon.Chat.ChainBuilder
  alias Ichor.Archon.Chat.Commands
  alias Ichor.Archon.Chat.TurnRunner

  @doc """
  Run a single conversation turn.

  Returns `{:ok, response_text_or_typed_map, updated_messages}` or `{:error, reason}`.
  """
  @spec chat(String.t(), list()) :: {:ok, String.t() | map(), list()} | {:error, term()}
  def chat("/" <> _ = input, messages) do
    case commands_module().run(input) do
      {:ok, response} -> {:ok, response, messages}
      {:error, reason} -> {:ok, %{type: :error, data: inspect(reason)}, messages}
    end
  end

  def chat(user_input, messages) do
    with {:ok, chain} <- chain_builder_module().build(),
         {:ok, response, history} <- turn_runner_module().run(chain, messages, user_input) do
      {:ok, response, history}
    end
  end

  defp commands_module do
    Application.get_env(:ichor, :archon_chat_commands_module, Commands)
  end

  defp chain_builder_module do
    Application.get_env(:ichor, :archon_chat_chain_builder_module, ChainBuilder)
  end

  defp turn_runner_module do
    Application.get_env(:ichor, :archon_chat_turn_runner_module, TurnRunner)
  end
end
