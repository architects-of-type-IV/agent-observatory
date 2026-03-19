defmodule Ichor.Tasks.Board do
  @moduledoc """
  Unified action layer for team board tasks, including signal emission.
  """

  alias Ichor.Tasks.TeamStore

  @doc "Create a task and emit a task_created signal for the team."
  @spec create_task(String.t(), map()) :: {:ok, map()} | {:error, term()}
  def create_task(team_name, attrs) do
    with {:ok, task} <- TeamStore.create_task(team_name, attrs) do
      emit(:task_created, team_name, %{task: task})
      {:ok, task}
    end
  end

  @doc "Update a task and emit a task_updated signal for the team."
  @spec update_task(String.t(), String.t(), map()) :: {:ok, map()} | {:error, term()}
  def update_task(team_name, task_id, changes) do
    with {:ok, task} <- TeamStore.update_task(team_name, task_id, changes) do
      emit(:task_updated, team_name, %{task: task})
      {:ok, task}
    end
  end

  @doc "Delete a task and emit a task_deleted signal for the team."
  @spec delete_task(String.t(), String.t()) :: :ok | {:error, term()}
  def delete_task(team_name, task_id) do
    case TeamStore.delete_task(team_name, task_id) do
      :ok ->
        emit(:task_deleted, team_name, %{task_id: task_id})
        :ok

      error ->
        error
    end
  end

  defdelegate get_task(team_name, task_id), to: TeamStore
  defdelegate list_tasks(team_name), to: TeamStore
  defdelegate next_task_id(team_name), to: TeamStore

  defp emit(signal, team_name, payload) do
    Ichor.Signals.emit(signal, team_name, payload)
    Ichor.Signals.emit(:tasks_updated, %{team_name: team_name})
  end
end
