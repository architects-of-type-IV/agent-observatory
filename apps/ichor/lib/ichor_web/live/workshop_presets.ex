defmodule IchorWeb.WorkshopPresets do
  @moduledoc """
  Preset team configurations and launch logic for the Workshop.
  """

  alias Ichor.Workshop.Presets

  @spec apply(Phoenix.LiveView.Socket.t(), String.t()) :: Phoenix.LiveView.Socket.t()
  def apply(socket, name) do
    state = Presets.apply(socket.assigns, name)

    socket
    |> Phoenix.Component.assign(:ws_team_name, state.ws_team_name)
    |> Phoenix.Component.assign(:ws_strategy, state.ws_strategy)
    |> Phoenix.Component.assign(:ws_default_model, state.ws_default_model)
    |> Phoenix.Component.assign(:ws_agents, state.ws_agents)
    |> Phoenix.Component.assign(:ws_next_id, state.ws_next_id)
    |> Phoenix.Component.assign(:ws_spawn_links, state.ws_spawn_links)
    |> Phoenix.Component.assign(:ws_comm_rules, state.ws_comm_rules)
  end

  # ── Spawn Order (topological sort for launch) ──────────────

  @spec spawn_order([map()], [map()]) :: [map()]
  defdelegate spawn_order(agents, spawn_links), to: Presets
end
