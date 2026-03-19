defmodule Ichor.Mes.CompletionHandler do
  @moduledoc """
  Reacts to DAG run completion by compiling and hot-loading the subsystem.
  Follows the ProjectIngestor pattern: subscribe to signal, call domain APIs.
  """

  use GenServer

  require Logger

  alias Ichor.Mes.SubsystemLoader
  alias Ichor.Projects
  alias Ichor.Signals

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:dag)
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Signals.Message{name: :dag_run_completed, data: data}, state) do
    handle_completion(data)
    {:noreply, state}
  end

  def handle_info(%Signals.Message{}, state), do: {:noreply, state}

  defp handle_completion(%{run_id: run_id}) do
    with {:ok, run} <- Projects.get_run(run_id),
         {:ok, node} <- resolve_node(run.node_id),
         {:ok, project} <- resolve_project(node.mes_project_id) do
      compile_and_load(project, run_id)
    else
      {:error, :no_node} ->
        Logger.debug("[MES.CompletionHandler] DAG run #{run_id} has no genesis node, skipping")

      {:error, :no_project} ->
        Logger.debug("[MES.CompletionHandler] Genesis node has no MES project, skipping")

      {:error, reason} ->
        Logger.warning(
          "[MES.CompletionHandler] Failed to resolve run #{run_id}: #{inspect(reason)}"
        )
    end
  end

  defp handle_completion(_data), do: :ok

  defp resolve_node(nil), do: {:error, :no_node}

  defp resolve_node(node_id) do
    case Projects.get_node(node_id) do
      {:ok, nil} -> {:error, :no_node}
      {:ok, node} -> {:ok, node}
      error -> error
    end
  end

  defp resolve_project(nil), do: {:error, :no_project}

  defp resolve_project(project_id) do
    case Projects.get_project(project_id) do
      {:ok, nil} -> {:error, :no_project}
      {:ok, project} -> {:ok, project}
      error -> error
    end
  end

  defp compile_and_load(project, run_id) do
    case SubsystemLoader.compile_and_load(project) do
      {:ok, modules} ->
        Projects.mark_loaded(project)

        Logger.info(
          "[MES.CompletionHandler] Loaded #{length(modules)} modules for #{project.subsystem}"
        )

      {:error, reason} ->
        Projects.mark_failed(project, inspect(reason))

        Signals.emit(:mes_subsystem_compile_failed, %{
          run_id: run_id,
          project_id: project.id,
          reason: inspect(reason)
        })

        Logger.warning(
          "[MES.CompletionHandler] Failed to load #{project.subsystem}: #{inspect(reason)}"
        )
    end
  end
end
