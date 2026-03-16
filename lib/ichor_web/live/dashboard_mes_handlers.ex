defmodule IchorWeb.DashboardMesHandlers do
  @moduledoc """
  Handle events for the MES (Manufacturing Execution System) view.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Ichor.Genesis.ModeSpawner
  alias Ichor.Genesis.Node, as: GenesisNode
  alias Ichor.Mes.{Project, Scheduler, SubsystemLoader}
  alias Ichor.Signals
  alias IchorWeb.DashboardMesResearchHandlers

  @spec dispatch(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def dispatch("toggle_mes_scheduler", _params, socket) do
    toggle_scheduler(Scheduler.paused?())

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

    socket
    |> assign(:selected_mes_project, project)
    |> assign(:genesis_node, load_genesis_node(project))
  end

  def dispatch("mes_start_mode", %{"mode" => mode, "project-id" => project_id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == project_id))
    genesis_node_id = get_in(socket.assigns, [:genesis_node, :id])

    with {:ok, node_id} <- ModeSpawner.ensure_genesis_node(genesis_node_id, project),
         {:ok, session} <- ModeSpawner.spawn_mode(mode, project_id, node_id) do
      socket
      |> assign(:genesis_node, load_genesis_node(project))
      |> put_flash(:info, "Mode #{String.upcase(mode)} team spawned: #{session}")
    else
      {:error, reason} ->
        put_flash(socket, :error, "Mode #{String.upcase(mode)} failed: #{inspect(reason)}")
    end
  end

  def dispatch("mes_gate_check", %{"node-id" => node_id}, socket) do
    report = run_gate_check(node_id)
    assign(socket, :gate_report, report)
  end

  def dispatch("mes_generate_dag", %{"node-id" => node_id}, socket) do
    case Ichor.Genesis.DagGenerator.generate(node_id) do
      {:ok, []} ->
        put_flash(socket, :info, "No subtasks found -- run Mode C first")

      {:ok, tasks} ->
        jsonl = Ichor.Genesis.DagGenerator.to_jsonl_string(tasks)
        dag_path = Path.join(File.cwd!(), "tasks.jsonl")
        File.write!(dag_path, jsonl <> "\n")
        put_flash(socket, :info, "DAG generated: #{length(tasks)} tasks written to tasks.jsonl")

      {:error, reason} ->
        put_flash(socket, :error, "DAG generation failed: #{inspect(reason)}")
    end
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

  defp toggle_scheduler(true), do: Scheduler.resume()
  defp toggle_scheduler(false), do: Scheduler.pause()

  @genesis_loads [:adrs, :features, :use_cases, :checkpoints, :conversations, :phases]

  defp load_genesis_node(nil), do: nil

  defp load_genesis_node(project) do
    case Ash.read(GenesisNode, filter: [mes_project_id: project.id], load: @genesis_loads) do
      {:ok, [node | _]} -> node
      _ -> nil
    end
  end

  defp run_gate_check(node_id) do
    with {:ok, node} <- GenesisNode.get(node_id),
         {:ok, loaded} <- Ash.load(node, @genesis_loads) do
      adrs = length(loaded.adrs)
      accepted_adrs = Enum.count(loaded.adrs, &(&1.status == :accepted))
      features = length(loaded.features)
      use_cases = length(loaded.use_cases)
      phases = length(loaded.phases)

      %{
        "node_id" => loaded.id,
        "current_status" => to_string(loaded.status),
        "adrs" => adrs,
        "accepted_adrs" => accepted_adrs,
        "features" => features,
        "use_cases" => use_cases,
        "checkpoints" => length(loaded.checkpoints),
        "phases" => phases,
        "ready_for_define" => adrs > 0 and accepted_adrs > 0,
        "ready_for_build" => features > 0 and use_cases > 0,
        "ready_for_complete" => phases > 0
      }
    else
      _ -> nil
    end
  end

  defp maybe_load_research(:research, socket) do
    DashboardMesResearchHandlers.load_research_data(socket)
  end

  defp maybe_load_research(_tab, socket), do: socket
end
