defmodule Observatory.Notes do
  @moduledoc """
  ETS-backed storage for event annotations and notes.
  Allows users to add contextual notes to specific events.
  """
  use GenServer
  require Logger

  @table_name :observatory_notes

  # ═══════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Add or update a note for a specific event.
  """
  def add_note(event_id, text) when is_binary(text) do
    GenServer.call(__MODULE__, {:add_note, event_id, text})
  end

  @doc """
  Get the note for a specific event.
  Returns `nil` if no note exists.
  """
  def get_note(event_id) do
    GenServer.call(__MODULE__, {:get_note, event_id})
  end

  @doc """
  List all notes with their event IDs.
  Returns a map of %{event_id => %{text: text, timestamp: timestamp}}
  """
  def list_notes do
    GenServer.call(__MODULE__, :list_notes)
  end

  @doc """
  Delete a note for a specific event.
  """
  def delete_note(event_id) do
    GenServer.call(__MODULE__, {:delete_note, event_id})
  end

  # ═══════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    # Create ETS table: {event_id, %{text: text, timestamp: timestamp}}
    :ets.new(@table_name, [:named_table, :public, :set])
    {:ok, %{}}
  end

  @impl true
  def handle_call({:add_note, event_id, text}, _from, state) do
    note = %{
      text: text,
      timestamp: DateTime.utc_now()
    }

    :ets.insert(@table_name, {event_id, note})
    {:reply, {:ok, note}, state}
  end

  def handle_call({:get_note, event_id}, _from, state) do
    result =
      case :ets.lookup(@table_name, event_id) do
        [{^event_id, note}] -> note
        [] -> nil
      end

    {:reply, result, state}
  end

  def handle_call(:list_notes, _from, state) do
    notes =
      :ets.tab2list(@table_name)
      |> Enum.map(fn {event_id, note} -> {event_id, note} end)
      |> Map.new()

    {:reply, notes, state}
  end

  def handle_call({:delete_note, event_id}, _from, state) do
    :ets.delete(@table_name, event_id)
    {:reply, :ok, state}
  end
end
