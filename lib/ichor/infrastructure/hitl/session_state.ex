defmodule Ichor.Infrastructure.HITL.SessionState do
  @moduledoc """
  Pure pause/resume state policy for HITL sessions.

  Manages two maps held in `HITLRelay`'s GenServer state:
  - `sessions` — maps `session_id => :paused | :normal`
  - `paused_at` — maps `session_id => DateTime.t()` (only for paused sessions)

  All functions are pure: they take the current state and return a new one,
  with no side effects.
  """

  @type sessions :: %{String.t() => :paused | :normal}
  @type paused_at :: %{String.t() => DateTime.t()}
  @type t :: %{sessions: sessions(), paused_at: paused_at()}

  @doc "Return the initial state."
  @spec new() :: t()
  def new, do: %{sessions: %{}, paused_at: %{}}

  @doc "Return `:paused` or `:normal` for `session_id`."
  @spec status(t(), String.t()) :: :paused | :normal
  def status(state, session_id), do: Map.get(state.sessions, session_id, :normal)

  @doc "Return `true` if the session is currently paused."
  @spec paused?(t(), String.t()) :: boolean()
  def paused?(state, session_id), do: status(state, session_id) == :paused

  @doc "Transition `session_id` to `:paused`. Returns updated state."
  @spec pause(t(), String.t()) :: t()
  def pause(state, session_id) do
    %{
      state
      | sessions: Map.put(state.sessions, session_id, :paused),
        paused_at: Map.put(state.paused_at, session_id, DateTime.utc_now())
    }
  end

  @doc "Transition `session_id` to `:normal`. Returns updated state."
  @spec resume(t(), String.t()) :: t()
  def resume(state, session_id) do
    %{
      state
      | sessions: Map.put(state.sessions, session_id, :normal),
        paused_at: Map.delete(state.paused_at, session_id)
    }
  end

  @doc "Return all currently paused session IDs."
  @spec paused_session_ids(t()) :: [String.t()]
  def paused_session_ids(state) do
    state.sessions
    |> Enum.filter(fn {_k, v} -> v == :paused end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc """
  Return session IDs that have been paused longer than `ttl_seconds`.
  Used by the sweep job to auto-release abandoned paused sessions.
  """
  @spec abandoned_since(t(), pos_integer()) :: [String.t()]
  def abandoned_since(state, ttl_seconds) do
    cutoff = DateTime.add(DateTime.utc_now(), -ttl_seconds, :second)

    state.paused_at
    |> Enum.filter(fn {_sid, paused_time} -> DateTime.compare(paused_time, cutoff) == :lt end)
    |> Enum.map(&elem(&1, 0))
  end

  @doc "Remove all state for the given `session_ids`. Returns updated state."
  @spec drop(t(), [String.t()]) :: t()
  def drop(state, session_ids) do
    %{
      state
      | sessions: Map.drop(state.sessions, session_ids),
        paused_at: Map.drop(state.paused_at, session_ids)
    }
  end
end
