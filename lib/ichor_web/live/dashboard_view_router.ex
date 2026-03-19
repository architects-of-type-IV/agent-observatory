defmodule IchorWeb.DashboardViewRouter do
  @moduledoc """
  Canonical view-mode router for the dashboard's internal screen model.
  """

  import Phoenix.Component, only: [assign: 3]

  @mode_mappings %{
    "command" => {:command, []},
    "activity" => {:activity, []},
    "pipeline" => {:pipeline, []},
    "forensic" => {:forensic, []},
    "control" => {:control, []},
    "fleet_command" => {:command, []},
    "overview" => {:command, []},
    "agents" => {:command, []},
    "teams" => {:command, []},
    "protocols" => {:command, []},
    "feed" => {:activity, [activity_tab: :feed]},
    "timeline" => {:activity, [activity_tab: :timeline]},
    "analytics" => {:activity, [activity_tab: :analytics]},
    "messages" => {:activity, [activity_tab: :messages]},
    "errors" => {:activity, [activity_tab: :errors]},
    "tasks" => {:pipeline, [pipeline_tab: :board]},
    "scheduler" => {:pipeline, [pipeline_tab: :scheduler]},
    "registry" => {:forensic, [forensic_tab: :registry]},
    "god_mode" => {:control, [control_tab: :emergency]},
    "session_cluster" => {:control, [control_tab: :sessions]}
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
