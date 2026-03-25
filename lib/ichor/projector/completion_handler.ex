defmodule Ichor.Projector.CompletionHandler do
  @moduledoc """
  Reacts to pipeline completion and dispatches the appropriate build output flow.
  Follows the ProjectIngestor pattern: subscribe to signal, call domain APIs.
  """

  use GenServer

  require Logger

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Events.Message
  alias Ichor.Factory.{Pipeline, Project}
  alias Ichor.Factory.PluginLoader
  alias Ichor.Signals

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:pipeline)
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Message{name: :pipeline_completed, data: data}, state) do
    handle_completion(data)
    {:noreply, state}
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  defp handle_completion(%{run_id: run_id}) do
    with {:ok, pipeline} <- Pipeline.get(run_id),
         {:ok, project} <- resolve_project(pipeline.project_id) do
      handle_output(project, run_id)
    else
      {:error, :no_project} ->
        Logger.debug("[MES.CompletionHandler] Pipeline run #{run_id} has no project, skipping")

      {:error, reason} ->
        Logger.warning(
          "[MES.CompletionHandler] Failed to resolve run #{run_id}: #{inspect(reason)}"
        )
    end
  end

  defp handle_completion(_data), do: :ok

  defp resolve_project(nil), do: {:error, :no_project}

  defp resolve_project(project_id) do
    case Project.get(project_id) do
      {:ok, nil} -> {:error, :no_project}
      {:ok, project} -> {:ok, project}
      error -> error
    end
  end

  defp handle_output(%{output_kind: "plugin"} = project, run_id) do
    case PluginLoader.compile_and_load(project) do
      {:ok, modules} ->
        Project.mark_loaded(project)

        Logger.info(
          "[MES.CompletionHandler] Loaded #{length(modules)} modules for #{project.plugin}"
        )

      {:error, reason} ->
        Project.mark_failed(project, inspect(reason))

        Events.emit(
          Event.new(
            "mes.plugin.compile_failed",
            run_id,
            %{
              run_id: run_id,
              project_id: project.id,
              reason: inspect(reason)
            },
            %{legacy_name: :mes_plugin_compile_failed}
          )
        )

        Logger.warning(
          "[MES.CompletionHandler] Failed to load #{project.plugin}: #{inspect(reason)}"
        )
    end
  end

  defp handle_output(project, run_id) do
    Events.emit(
      Event.new(
        "mes.output.unhandled",
        run_id,
        %{
          run_id: run_id,
          project_id: project.id,
          output_kind: project.output_kind
        },
        %{legacy_name: :mes_output_unhandled}
      )
    )

    Logger.info(
      "[MES.CompletionHandler] No output handler for project #{project.id} kind=#{project.output_kind}"
    )
  end
end
