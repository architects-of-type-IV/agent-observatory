defmodule Ichor.Archon.Chat.ActionRunner do
  @moduledoc """
  Thin Ash action execution boundary for Archon command dispatch.
  """

  @spec run(atom(), module(), atom(), map()) ::
          {:ok, %{type: atom(), data: term()}} | {:error, term()}
  def run(type, resource, action, params) do
    case Ash.ActionInput.for_action(resource, action, params) |> Ash.run_action() do
      {:ok, result} -> {:ok, %{type: type, data: result}}
      {:error, reason} -> {:error, reason}
    end
  end
end
