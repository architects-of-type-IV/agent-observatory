defmodule Observatory.Mesh.EntropyTracker do
  @moduledoc """
  Stub module for entropy tracking. Will be replaced with a full
  implementation in Phase 3.
  """

  @doc """
  Records an entropy observation and returns the computed score.

  Stub implementation: returns the input score unchanged.
  """
  @spec record_and_score(String.t(), float() | nil) :: float() | nil
  def record_and_score(_agent_id, score), do: score
end
