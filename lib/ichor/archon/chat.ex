defmodule Ichor.Archon.Chat do
  @moduledoc """
  Archon conversation engine.

  Runs a single conversation turn: takes user input + history,
  routes slash commands directly, or executes an LLM-backed turn.
  Stateless -- conversation state lives in the caller (LiveView assigns).
  """

  alias Ichor.Archon.Chat.ChainBuilder
  alias Ichor.Archon.Chat.CommandRegistry
  alias Ichor.Archon.Chat.TurnRunner

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
    with {:ok, chain} <- chain_builder_module().build() do
      turn_runner_module().run(chain, messages, user_input)
    end
  end

  defp run_command(input) do
    with {:ok, command} <- parse_command(input) do
      CommandRegistry.dispatch(command)
    end
  end

  defp parse_command(input) when is_binary(input) do
    trimmed = String.trim(input)
    [command | rest] = String.split(trimmed, " ", parts: 2)
    remainder = List.first(rest)

    {:ok, %{raw: trimmed, command: command, remainder: remainder}}
  end

  defp chain_builder_module do
    Application.get_env(:ichor, :archon_chat_chain_builder_module, ChainBuilder)
  end

  defp turn_runner_module do
    Application.get_env(:ichor, :archon_chat_turn_runner_module, TurnRunner)
  end
end
