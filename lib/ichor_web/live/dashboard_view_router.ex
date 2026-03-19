defmodule IchorWeb.DashboardViewRouter do
  @moduledoc """
  Canonical view-mode router for the dashboard's internal screen model.
  """

  import Phoenix.Component, only: [assign: 3]

  @mode_mappings %{
    "command" => {:command, []},
    "pipeline" => {:pipeline, []},
    "fleet_command" => {:command, []},
    "overview" => {:command, []},
    "agents" => {:command, []},
    "teams" => {:command, []},
    "protocols" => {:command, []},
    "feed" => {:command, [activity_tab: :feed]},
    "timeline" => {:command, [activity_tab: :feed]},
    "analytics" => {:command, [activity_tab: :feed]},
    "messages" => {:command, [activity_tab: :comms]},
    "errors" => {:command, [activity_tab: :feed]},
    "tasks" => {:pipeline, []},
    "scheduler" => {:pipeline, []},
    "registry" => {:command, []},
    "god_mode" => {:command, []},
    "session_cluster" => {:command, []}
  }

  def resolve(mode) when is_atom(mode), do: {mode, []}

  def resolve(mode) when is_binary(mode) do
    Map.get_lazy(@mode_mappings, mode, fn -> resolve_dynamic(mode) end)
  end

  def assign_view(socket, mode) do
    {view_mode, sub_tab_assigns} = resolve(mode)

    socket
    |> assign(:view_mode, view_mode)
    |> assign_sub_tabs(sub_tab_assigns)
    |> Phoenix.LiveView.push_event("view_mode_changed", %{view_mode: Atom.to_string(view_mode)})
  end

  defp assign_sub_tabs(socket, sub_tab_assigns) do
    Enum.reduce(sub_tab_assigns, socket, fn {key, value}, acc -> assign(acc, key, value) end)
  end

  defp resolve_dynamic(mode) do
    {String.to_existing_atom(mode), []}
  rescue
    ArgumentError -> {:command, []}
  end
end
