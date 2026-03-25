defmodule IchorWeb.Components.SettingsComponents do
  @moduledoc """
  Settings page -- category sidebar with per-category content panels.
  Currently supports Projects; other categories are stubbed.
  """

  use Phoenix.Component

  import IchorWeb.UI, only: [button: 1]

  embed_templates "settings_components/*"

  @categories [
    {:projects, "Projects", true},
    {:operational, "Operational Thresholds", false},
    {:integrations, "Integrations", false},
    {:ui_preferences, "UI Preferences", false},
    {:feature_flags, "Feature Flags", false}
  ]

  defp categories, do: @categories

  defp category_active?(slug, current), do: slug == current

  defp filtered_entries(entries, ""), do: entries
  defp filtered_entries(entries, nil), do: entries

  defp filtered_entries(entries, filter) do
    down = String.downcase(filter)
    Enum.filter(entries, &String.contains?(String.downcase(&1), down))
  end

  defp truncate_path(nil), do: ""

  defp truncate_path(path) do
    parts = Path.split(path)

    case length(parts) do
      n when n <= 2 -> path
      _ -> ".../#{Enum.at(parts, -2)}/#{Enum.at(parts, -1)}"
    end
  end
end
