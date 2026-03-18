defmodule Ichor.Archon.Chat.Commands do
  @moduledoc """
  Public entrypoint for Archon slash command parsing and dispatch.
  """

  alias Ichor.Archon.Chat.CommandParser
  alias Ichor.Archon.Chat.CommandRegistry

  @spec run(String.t()) :: {:ok, %{type: atom(), data: term()}} | {:error, term()}
  def run(input) do
    with {:ok, command} <- parser_module().parse(input) do
      registry_module().dispatch(command)
    end
  end

  defp parser_module do
    Application.get_env(:ichor, :archon_chat_command_parser_module, CommandParser)
  end

  defp registry_module do
    Application.get_env(:ichor, :archon_chat_command_registry_module, CommandRegistry)
  end
end
