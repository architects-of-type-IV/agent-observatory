defmodule IchorWeb.DashboardMesHandlers do
  @moduledoc "Event handlers for the MES factory view."

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [put_flash: 3]

  alias Ichor.Factory.{
    PipelineCompiler,
    MesScheduler,
    Project,
    Spawn
  }

  alias Ichor.Factory.PluginLoader

  alias Ichor.Signals

  @spec dispatch(String.t(), map(), Phoenix.LiveView.Socket.t()) :: Phoenix.LiveView.Socket.t()
  def dispatch("toggle_mes_scheduler", _params, socket) do
    socket
    |> toggle_scheduler(MesScheduler.paused?())
    |> assign(:mes_scheduler_status, fetch_scheduler_status())
  end

  def dispatch("mes_deselect_project", _params, socket) do
    socket
    |> assign(:selected_mes_project, nil)
    |> assign(:planning_project, nil)
    |> assign(:planning_selected, nil)
    |> assign(:gate_report, nil)
  end

  def dispatch("mes_select_project", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))

    socket
    |> assign(:selected_mes_project, project)
    |> assign(:planning_project, load_planning_project(project))
  end

  def dispatch("mes_start_mode", %{"mode" => mode, "project-id" => project_id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == project_id))

    planning_project_id = socket.assigns.planning_project && socket.assigns.planning_project.id

    with {:ok, target_project_id} <- Spawn.ensure_planning_project(planning_project_id, project),
         {:ok, session} <- Spawn.spawn(:planning, mode, project_id, target_project_id) do
      socket
      |> assign(:planning_project, load_planning_project_by_id(target_project_id))
      |> put_flash(:info, "Mode #{String.upcase(mode)} team spawned: #{session}")
    else
      {:error, reason} ->
        put_flash(socket, :error, "Mode #{String.upcase(mode)} failed: #{inspect(reason)}")
    end
  end

  def dispatch("mes_gate_check", %{"project-id" => project_id}, socket) do
    report = run_gate_check(project_id)
    assign(socket, :gate_report, report)
  end

  def dispatch("mes_generate_dag", %{"project-id" => project_id}, socket) do
    case PipelineCompiler.generate(project_id) do
      {:ok, []} ->
        put_flash(socket, :info, "No subtasks found -- run Mode C first")

      {:ok, tasks} ->
        jsonl = PipelineCompiler.to_jsonl_string(tasks)
        tasks_path = Path.join(File.cwd!(), "tasks.jsonl")
        File.write!(tasks_path, jsonl <> "\n", [:append])
        Signals.emit(:mes_pipeline_generated, %{project_id: project_id})
        put_flash(socket, :info, "DAG generated: #{length(tasks)} tasks appended to tasks.jsonl")

      {:error, reason} ->
        put_flash(socket, :error, "DAG generation failed: #{inspect(reason)}")
    end
  end

  def dispatch("mes_launch_dag", %{"project-id" => project_id}, socket) do
    case Spawn.spawn(:pipeline, project_id, project_id) do
      {:ok, %{session: session}} ->
        Signals.emit(:mes_pipeline_launched, %{project_id: project_id, session: session})

        socket
        |> assign(:planning_project, load_planning_project_by_id(project_id))
        |> put_flash(:info, "Build team launched: #{session}")

      {:error, reason} ->
        put_flash(socket, :error, "Build failed: #{inspect(reason)}")
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

  @planning_tabs %{
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

  def dispatch("planning_switch_tab", %{"tab" => tab}, socket) do
    socket
    |> assign(:planning_sub_tab, Map.get(@planning_tabs, tab, :decisions))
    |> assign(:planning_selected, nil)
  end

  def dispatch("planning_select_artifact", %{"type" => type, "id" => id}, socket) do
    assign(socket, :planning_selected, {Map.get(@artifact_types, type, :adr), id})
  end

  def dispatch("planning_close_reader", _params, socket) do
    assign(socket, :planning_selected, nil)
  end

  def dispatch("mes_load_plugin", %{"id" => id}, socket) do
    project = Enum.find(socket.assigns.mes_projects, &(&1.id == id))

    case PluginLoader.compile_and_load(project) do
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

  defp toggle_scheduler(socket, true) do
    MesScheduler.resume()
    put_flash(socket, :info, "MES resumed")
  end

  defp toggle_scheduler(socket, false) do
    MesScheduler.pause()
    put_flash(socket, :info, "MES paused")
  end

  @scheduler_fallback %{tick: 0, active_runs: 0, next_tick_in: 60_000, paused: false}

  def fetch_scheduler_status do
    MesScheduler.status()
  catch
    :exit, _ -> @scheduler_fallback
  end

  defp load_planning_project_by_id(project_id) do
    case Project.get(project_id) do
      {:ok, project} -> project
      _ -> nil
    end
  end

  defp load_planning_project(nil), do: nil

  defp load_planning_project(project) do
    load_planning_project_by_id(project.id)
  end

  defp run_gate_check(project_id) do
    case Project.gate_check(project_id) do
      {:ok, report} -> normalize_gate_report(report)
      _ -> nil
    end
  end

  defp normalize_gate_report(report) when is_map(report) do
    %{
      project_id: report["project_id"],
      current_status: report["planning_stage"],
      output_kind: report["output_kind"],
      adrs: report["adrs"] || 0,
      accepted_adrs: report["accepted_adrs"] || 0,
      features: report["features"] || 0,
      use_cases: report["use_cases"] || 0,
      checkpoints: report["checkpoints"] || 0,
      phases: report["phases"] || 0,
      ready_for_define: report["ready_for_define"] || false,
      ready_for_build: report["ready_for_build"] || false,
      ready_for_complete: report["ready_for_complete"] || false
    }
  end
end
