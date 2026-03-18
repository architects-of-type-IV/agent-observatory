defmodule IchorWeb.DashboardSwarmHandlers do
  @moduledoc """
  Compatibility wrapper for the old swarm-named dashboard pipeline handlers.
  """

  defdelegate dispatch(event, params, socket), to: IchorWeb.DashboardDagHandlers
  defdelegate handle_add_project(params, socket), to: IchorWeb.DashboardDagHandlers
end
