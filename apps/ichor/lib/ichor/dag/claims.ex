defmodule Ichor.Dag.Claims do
  @moduledoc """
  Task-claim and corrective action boundary for DAG pipelines.
  """

  alias Ichor.SwarmMonitor

  @spec claim_task(String.t(), String.t()) :: :ok | {:error, term()}
  def claim_task(task_id, agent_name), do: SwarmMonitor.claim_task(task_id, agent_name)

  @spec heal_task(String.t()) :: :ok | {:error, term()}
  def heal_task(task_id), do: SwarmMonitor.heal_task(task_id)

  @spec reassign_task(String.t(), String.t()) :: :ok | {:error, term()}
  def reassign_task(task_id, new_owner), do: SwarmMonitor.reassign_task(task_id, new_owner)

  @spec reset_stale(non_neg_integer()) :: :ok | {:error, term()}
  def reset_stale(threshold_min \\ 10), do: SwarmMonitor.reset_all_stale(threshold_min)
end
