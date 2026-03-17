defmodule IchorWeb.DashboardMesHandlers do
  @moduledoc "Event handlers for the MES factory view."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Ichor.Genesis.{DagGenerator, ModeSpawner}
  alias Ichor.Genesis.Node, as: GenesisNode
  alias Ichor.Mes.{Project, Scheduler, SubsystemLoader}
  alias Ichor.Signals

  @spec dispatch(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def dispatch("toggle_mes_scheduler", _params, socket) do
    toggle_scheduler(Scheduler.paused?())
    assign(socket, :mes_scheduler_status, fetch_scheduler_status())
  end

  def dispatch("mes_deselect_project", _params, socket) do
    socket
    |> assign(:selected_mes_project, nil)
    |> assign(:genesis_node, nil)
    |> assign(:genesis_selected, nil)
    |> assign(:gate_report, nil)
  end

  def dispatch("mes_select_project", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))

    socket
    |> assign(:selected_mes_project, project)
    |> assign(:genesis_node, load_genesis_node(project))
  end

  def dispatch("mes_start_mode", %{"mode" => mode, "project-id" => project_id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == project_id))

    genesis_node_id = socket.assigns.genesis_node && socket.assigns.genesis_node.id

    with {:ok, node_id} <- ModeSpawner.ensure_genesis_node(genesis_node_id, project),
         {:ok, session} <- ModeSpawner.spawn_mode(mode, project_id, node_id) do
      socket
      |> assign(:genesis_node, load_genesis_node_by_id(node_id))
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
    case DagGenerator.generate(node_id) do
      {:ok, []} ->
        put_flash(socket, :info, "No subtasks found -- run Mode C first")

      {:ok, tasks} ->
        jsonl = DagGenerator.to_jsonl_string(tasks)
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

  @genesis_sub_tabs %{
    "decisions" => :decisions,
    "requirements" => :requirements,
    "checkpoints" => :checkpoints,
    "roadmap" => :roadmap
  }
  @artifact_types %{
    "adr" => :adr,
    "feature" => :feature,
    "use_case" => :use_case,
    "checkpoint" => :checkpoint,
    "conversation" => :conversation,
    "phase" => :phase
  }

  def dispatch("genesis_switch_tab", %{"tab" => tab}, socket) do
    socket
    |> assign(:genesis_sub_tab, Map.get(@genesis_sub_tabs, tab, :decisions))
    |> assign(:genesis_selected, nil)
  end

  def dispatch("genesis_select_artifact", %{"type" => type, "id" => id}, socket) do
    assign(socket, :genesis_selected, {Map.get(@artifact_types, type, :adr), id})
  end

  def dispatch("genesis_close_reader", _params, socket) do
    assign(socket, :genesis_selected, nil)
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

  defp toggle_scheduler(true), do: Scheduler.resume()
  defp toggle_scheduler(false), do: Scheduler.pause()

  @scheduler_fallback %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false}

  def fetch_scheduler_status do
    try do
      Scheduler.status()
    catch
      :exit, _ -> @scheduler_fallback
    end
  end

  @genesis_loads [
    :adrs,
    :features,
    :use_cases,
    :checkpoints,
    :conversations,
    phases: [sections: [tasks: [:subtasks]]]
  ]

  defp load_genesis_node_by_id(node_id) do
    case GenesisNode.get(node_id, load: @genesis_loads) do
      {:ok, node} -> node
      _ -> nil
    end
  end

  defp load_genesis_node(nil), do: nil

  defp load_genesis_node(project) do
    case GenesisNode.by_project(project.id, load: @genesis_loads) do
      {:ok, [node | _]} -> node
      _ -> nil
    end
  end

  defp run_gate_check(node_id) do
    case GenesisNode.get(node_id, load: @genesis_loads) do
      {:ok, loaded} -> build_gate_report(loaded)
      _ -> nil
    end
  end

  defp build_gate_report(loaded) do
    adrs = length(loaded.adrs)
    accepted = Enum.count(loaded.adrs, &(&1.status == :accepted))
    features = length(loaded.features)
    use_cases = length(loaded.use_cases)
    phases = length(loaded.phases)

    %{
      node_id: loaded.id,
      current_status: to_string(loaded.status),
      adrs: adrs,
      accepted_adrs: accepted,
      features: features,
      use_cases: use_cases,
      checkpoints: length(loaded.checkpoints),
      phases: phases,
      ready_for_define: adrs > 0 and accepted > 0,
      ready_for_build: features > 0 and use_cases > 0,
      ready_for_complete: phases > 0
    }
  end
end
