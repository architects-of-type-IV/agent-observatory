defmodule Ichor.Signals.TraceEvent do
  @moduledoc false

  @enforce_keys [:id, :kind, :name, :timestamp]
  defstruct [
    :id,
    :kind,
    :name,
    :session_id,
    source: %{},
    target: %{},
    payload: %{},
    transport: %{},
    audit: %{},
    timestamp: nil
  ]

  @type t :: %__MODULE__{
          id: binary(),
          kind: atom(),
          name: atom(),
          session_id: binary() | nil,
          source: map(),
          target: map(),
          timestamp: DateTime.t(),
          payload: map(),
          transport: map(),
          audit: map()
        }
end
