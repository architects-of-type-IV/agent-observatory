defmodule Ichor.Notes do
  @moduledoc """
  ETS-backed storage for event annotations and notes.

  Call `Ichor.Notes.init/0` once at application startup before any other
  function is used. The ETS table is public so reads bypass any process
  bottleneck.
  """

  @table_name :ichor_notes
  @max_notes 1000

  @type note :: %{text: String.t(), timestamp: DateTime.t()}

  @doc "Create the ETS table. Must be called once at startup."
  @spec init() :: :ok
  def init do
    :ets.new(@table_name, [:named_table, :public, :set])
    :ok
  end

  @doc """
  Add or update a note for a specific event.
  Evicts the oldest entry when the table is at capacity.
  """
  @spec add_note(String.t(), String.t()) :: {:ok, note()}
  def add_note(event_id, text) when is_binary(text) do
    note = %{text: text, timestamp: DateTime.utc_now()}

    if :ets.info(@table_name, :size) >= @max_notes do
      oldest =
        @table_name
        |> :ets.tab2list()
        |> Enum.min_by(fn {_id, n} -> n.timestamp end, DateTime)
        |> elem(0)

      :ets.delete(@table_name, oldest)
    end

    :ets.insert(@table_name, {event_id, note})
    {:ok, note}
  end

  @doc """
  Get the note for a specific event.
  Returns `nil` if no note exists.
  """
  @spec get_note(String.t()) :: note() | nil
  def get_note(event_id) do
    case :ets.lookup(@table_name, event_id) do
      [{^event_id, note}] -> note
      [] -> nil
    end
  end

  @doc """
  List all notes.
  Returns a map of `%{event_id => %{text: text, timestamp: timestamp}}`.
  """
  @spec list_notes() :: %{String.t() => note()}
  def list_notes do
    @table_name
    |> :ets.tab2list()
    |> Map.new()
  end

  @doc "Delete the note for a specific event."
  @spec delete_note(String.t()) :: :ok
  def delete_note(event_id) do
    :ets.delete(@table_name, event_id)
    :ok
  end
end
