defmodule Ichor.Signal.Payload do
  @moduledoc """
  The broadcast struct for all ICHOR signals.

  Pattern match on this in `handle_info`:

      def handle_info(%Ichor.Signal.Payload{name: :heartbeat, data: data}, state)
  """

  @enforce_keys [:name, :category, :data, :ts, :source]
  defstruct [:name, :category, :data, :ts, :source]

  @type t :: %__MODULE__{
          name: atom(),
          category: atom(),
          data: map(),
          ts: integer(),
          source: pid()
        }

  @spec build(atom(), atom(), map()) :: t()
  def build(name, category, data) do
    %__MODULE__{
      name: name,
      category: category,
      data: data,
      ts: System.monotonic_time(:millisecond),
      source: self()
    }
  end
end
