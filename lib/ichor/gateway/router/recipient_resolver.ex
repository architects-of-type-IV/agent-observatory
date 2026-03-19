defmodule Ichor.Gateway.Router.RecipientResolver do
  @moduledoc """
  Resolves gateway channel patterns into recipient maps.
  """

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.AgentRegistry.AgentEntry

  @spec resolve(String.t()) :: [map()]
  def resolve("agent:" <> name) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if id == name || meta[:short_name] == name || meta[:name] == name do
        [recipient_from_meta(id, meta)]
      else
        []
      end
    end)
  end

  def resolve("session:" <> sid) do
    case AgentProcess.lookup(sid) do
      {_pid, meta} -> [recipient_from_meta(sid, meta)]
      nil -> []
    end
  end

  def resolve("team:" <> team_name) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:team] == team_name, do: [recipient_from_meta(id, meta)], else: []
    end)
  end

  def resolve("role:" <> role_str) do
    role = AgentEntry.role_from_string(role_str)

    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:role] == role, do: [recipient_from_meta(id, meta)], else: []
    end)
  end

  def resolve("fleet:" <> _) do
    Enum.flat_map(AgentProcess.list_all(), fn {id, meta} ->
      if meta[:status] == :active, do: [recipient_from_meta(id, meta)], else: []
    end)
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
