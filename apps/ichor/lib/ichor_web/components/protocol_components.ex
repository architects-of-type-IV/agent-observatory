defmodule IchorWeb.Components.ProtocolComponents do
  @moduledoc """
  Protocols view -- cross-protocol message tracing and channel statistics.
  Shows how messages flow through HTTP, PubSub, Mailbox, and CommandQueue.
  """

  use Phoenix.Component
  import IchorWeb.DashboardFormatHelpers

  alias Ichor.Gateway.AgentRegistry.AgentEntry

  embed_templates "protocol_components/*"

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp short_id(nil), do: "?"
  defp short_id("unknown"), do: "?"
  defp short_id("system"), do: "system"
  defp short_id("broadcast"), do: "all"
  defp short_id(id), do: AgentEntry.short_id(id)

  defp trace_type_label(:send_message), do: "message"
  defp trace_type_label(:team_create), do: "team"
  defp trace_type_label(:agent_spawn), do: "spawn"
  defp trace_type_label(other), do: to_string(other)

  defp trace_type_color(:send_message), do: "bg-interactive/15 text-interactive"
  defp trace_type_color(:team_create), do: "bg-cyan/15 text-cyan"
  defp trace_type_color(:agent_spawn), do: "bg-brand/15 text-brand"
  defp trace_type_color(_), do: "bg-highlight text-default"

  defp hop_status_color(:received), do: "bg-success"
  defp hop_status_color(:delivered), do: "bg-success"
  defp hop_status_color(:broadcast), do: "bg-cyan"
  defp hop_status_color(:pending), do: "bg-brand-muted"
  defp hop_status_color(:read), do: "bg-success"
  defp hop_status_color(_), do: "bg-low"

  defp hop_status_text(:received), do: "text-success"
  defp hop_status_text(:delivered), do: "text-success"
  defp hop_status_text(:broadcast), do: "text-cyan"
  defp hop_status_text(:pending), do: "text-brand"
  defp hop_status_text(:read), do: "text-success"
  defp hop_status_text(_), do: "text-muted"

  defp build_agent_name_map(teams) when is_list(teams) do
    teams
    |> Enum.flat_map(&team_name_entries/1)
    |> Map.new()
  end

  defp build_agent_name_map(_), do: %{}

  defp team_name_entries(team) do
    Enum.flat_map(team.members, fn member ->
      id = member[:agent_id] || member[:session_id]
      name = member[:name] || member[:agent_type]
      if id && name, do: [{id, "#{name}@#{team.name}"}], else: []
    end)
  end

  defp resolve_agent_label(nil, _map), do: "?"
  defp resolve_agent_label("unknown", _map), do: "?"
  defp resolve_agent_label("system", _map), do: "system"
  defp resolve_agent_label("broadcast", _map), do: "broadcast"
  defp resolve_agent_label("operator", _map), do: "operator"
  defp resolve_agent_label("dashboard", _map), do: "operator"

  defp resolve_agent_label(id, name_map) do
    case Map.get(name_map, id) do
      nil ->
        case String.split(id, "@") do
          [agent, team] -> "#{agent}@#{team}"
          _ -> AgentEntry.short_id(id)
        end

      name ->
        name
    end
  end

  defp format_timestamp(%DateTime{} = dt), do: Calendar.strftime(dt, "%H:%M:%S")
  defp format_timestamp(_), do: ""
end
