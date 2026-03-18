defmodule IchorWeb.Presentation do
  @moduledoc """
  Shared presentation helpers for IDs, timestamps, badges, and safe display values.
  """

  alias Ichor.Gateway.AgentRegistry.AgentEntry

  def short_id(nil), do: "?"
  def short_id("unknown"), do: "?"
  def short_id("system"), do: "system"
  def short_id("broadcast"), do: "all"
  def short_id("operator"), do: "operator"
  def short_id("dashboard"), do: "operator"
  def short_id(id) when is_binary(id), do: AgentEntry.short_id(id)
  def short_id(_), do: "?"

  def format_time(nil, _format), do: ""
  def format_time(%DateTime{} = dt, format), do: Calendar.strftime(dt, format)

  def format_time(ts, format) when is_binary(ts) do
    case DateTime.from_iso8601(ts) do
      {:ok, dt, _} -> Calendar.strftime(dt, format)
      _ -> ts
    end
  end

  def format_time(_, _format), do: ""

  def safe_string(nil), do: ""
  def safe_string(val) when is_binary(val), do: val
  def safe_string(val) when is_atom(val), do: to_string(val)
  def safe_string(val), do: inspect(val)

  def archon_status_badge_class(status) when is_atom(status),
    do: archon_status_badge_class(to_string(status))

  def archon_status_badge_class("active"), do: "archon-badge-ok"
  def archon_status_badge_class("paused"), do: "archon-badge-warn"
  def archon_status_badge_class(_), do: "archon-badge-dim"

  def archon_health_badge_class("healthy"), do: "archon-badge-ok"
  def archon_health_badge_class("degraded"), do: "archon-badge-warn"
  def archon_health_badge_class("critical"), do: "archon-badge-fail"
  def archon_health_badge_class(_), do: "archon-badge-dim"

  def archon_attention_badge_class(:critical), do: "archon-badge-fail"
  def archon_attention_badge_class("critical"), do: "archon-badge-fail"
  def archon_attention_badge_class(:high), do: "archon-badge-warn"
  def archon_attention_badge_class("high"), do: "archon-badge-warn"
  def archon_attention_badge_class(_), do: "archon-badge-dim"

  def health_bg_class(:healthy), do: "bg-success"
  def health_bg_class(:warning), do: "bg-brand"
  def health_bg_class(:critical), do: "bg-error"
  def health_bg_class(_), do: "bg-highlight"

  def health_text_class(:healthy), do: "text-success"
  def health_text_class(:warning), do: "text-brand"
  def health_text_class(:critical), do: "text-error"
  def health_text_class(_), do: "text-low"
end
