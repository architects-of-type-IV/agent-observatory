defmodule IchorWeb.DashboardMesHandlers do
  @moduledoc """
  Handle events for the MES (Manufacturing Execution System) view.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Ichor.Mes.{Project, Scheduler, SubsystemLoader}
  alias Ichor.Signals
  alias IchorWeb.DashboardMesResearchHandlers

  @spec dispatch(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def dispatch("toggle_mes_scheduler", _params, socket) do
    if Scheduler.paused?() do
      Scheduler.resume()
    else
      Scheduler.pause()
    end

    status =
      try do
        Scheduler.status()
      catch
        :exit, _ -> %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false}
      end

    assign(socket, :mes_scheduler_status, status)
  end

  def dispatch("mes_select_project", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))
    assign(socket, :selected_mes_project, project)
  end

  def dispatch("mes_pick_up", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))

    case Project.pick_up(project, "manual") do
      {:ok, _} ->
        Signals.emit(:mes_project_picked_up, %{project_id: id, session_id: "manual"})
        assign(socket, :mes_projects, Project.list_all!())

      {:error, reason} ->
        put_flash(socket, :error, "Failed to pick up: #{inspect(reason)}")
    end
  end

  def dispatch("mes_switch_tab", %{"tab" => tab}, socket) do
    tab_atom = String.to_existing_atom(tab)
    socket = assign(socket, :mes_tab, tab_atom)
    maybe_load_research(tab_atom, socket)
  end

  def dispatch("mes_research_" <> _ = event, params, socket) do
    DashboardMesResearchHandlers.dispatch(event, params, socket)
  end

  def dispatch("mes_select_research_" <> _ = event, params, socket) do
    DashboardMesResearchHandlers.dispatch(event, params, socket)
  end

  def dispatch("mes_load_subsystem", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))

    case SubsystemLoader.compile_and_load(project) do
      {:ok, modules} ->
        Project.mark_loaded(project)

        socket
        |> assign(:mes_projects, Project.list_all!())
        |> put_flash(:info, "Loaded #{length(modules)} modules")

      {:error, reason} ->
        Project.mark_failed(project, reason)

        socket
        |> assign(:mes_projects, Project.list_all!())
        |> put_flash(:error, reason)
    end
  end

  # ── Private ─────────────────────────────────────────────────────────

  defp maybe_load_research(:research, socket) do
    DashboardMesResearchHandlers.load_research_data(socket)
  end

  defp maybe_load_research(_tab, socket), do: socket
end
