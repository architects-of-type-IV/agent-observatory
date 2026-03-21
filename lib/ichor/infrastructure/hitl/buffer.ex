defmodule Ichor.Infrastructure.HITL.Buffer do
  @moduledoc """
  ETS-backed buffer for messages held while a session is paused.

  Keys are `{session_id, monotonic_timestamp}` so that messages for the same
  session are ordered by insertion time.  The table is created as
  `:ordered_set` so ETS's natural key ordering matches arrival order.

  This module owns no process state — all operations are direct ETS calls,
  making it callable from any process that has access to the named table.
  """

  @table :hitl_buffer

  @doc "Create the ETS table. Must be called once during `HITLRelay.init/1`."
  @spec create_table() :: :ok
  def create_table do
    :ets.new(@table, [:ordered_set, :public, :named_table])
    :ok
  end

  @doc "Insert a message into the buffer for `session_id`."
  @spec insert(String.t(), map()) :: :ok
  def insert(session_id, message) do
    key = {session_id, System.monotonic_time()}
    :ets.insert(@table, {key, message})
    :ok
  end

  @doc "Return all buffered messages for `session_id` in arrival order."
  @spec fetch(String.t()) :: [{key :: term(), map()}]
  def fetch(session_id) do
    :ets.match_object(@table, {{session_id, :_}, :_})
    |> Enum.sort_by(fn {{_sid, ts}, _msg} -> ts end)
  end

  @doc "Delete a single entry by its ETS key."
  @spec delete(term()) :: :ok
  def delete(key) do
    :ets.delete(@table, key)
    :ok
  end

  @doc "Delete all buffered messages for `session_id`. Returns the count deleted."
  @spec discard(String.t()) :: non_neg_integer()
  def discard(session_id) do
    entries = fetch(session_id)
    Enum.each(entries, fn {key, _msg} -> :ets.delete(@table, key) end)
    length(entries)
  end

  @doc "Rewrite the payload of a buffered message identified by `trace_id`."
  @spec rewrite(String.t(), String.t(), map()) :: :ok | {:error, :not_found}
  def rewrite(session_id, trace_id, new_payload) do
    case Enum.find(fetch(session_id), fn {_key, msg} -> Map.get(msg, :trace_id) == trace_id end) do
      {key, msg} ->
        :ets.insert(@table, {key, Map.put(msg, :payload, new_payload)})
        :ok

      nil ->
        {:error, :not_found}
    end
  end

  @doc "Return the number of buffered messages for `session_id`."
  @spec count(String.t()) :: non_neg_integer()
  def count(session_id) do
    length(:ets.match_object(@table, {{session_id, :_}, :_}))
  end
end
