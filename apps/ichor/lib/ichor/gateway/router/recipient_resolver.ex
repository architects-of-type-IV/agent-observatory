defmodule Ichor.Gateway.Router.RecipientResolver do
  @moduledoc """
  Resolves gateway channel patterns into recipient maps.
  """

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.AgentRegistry.AgentEntry

  @spec resolve(String.t()) :: [map()]
  def resolve("agent:" <> name) do
    AgentProcess.list_all()
    |> Enum.filter(fn {id, meta} ->
      id == name || meta[:short_name] == name || meta[:name] == name
    end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  def resolve("session:" <> sid) do
    case AgentProcess.lookup(sid) do
      {_pid, meta} -> [recipient_from_meta(sid, meta)]
      nil -> []
    end
  end

  def resolve("team:" <> team_name) do
    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:team] == team_name end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  def resolve("role:" <> role_str) do
    role = AgentEntry.role_from_string(role_str)

    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:role] == role end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  def resolve("fleet:" <> _) do
    AgentProcess.list_all()
    |> Enum.filter(fn {_id, meta} -> meta[:status] == :active end)
    |> Enum.map(fn {id, meta} -> recipient_from_meta(id, meta) end)
  end

  def resolve(_unknown), do: []

  defp recipient_from_meta(id, meta) do
    %{
      id: id,
      session_id: meta[:session_id] || id,
      channels: meta[:channels] || %{}
    }
  end
end
