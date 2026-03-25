defmodule Ichor.Events.Message do
  @moduledoc """
  The single message envelope for all ICHOR event broadcasts.

  Every published signal uses this shape. Consumers pattern match on it:

      def handle_info(%Ichor.Events.Message{name: :heartbeat, data: data}, state)
  """

  @enforce_keys [:name, :kind, :domain, :data, :timestamp]
  defstruct [
    :name,
    :kind,
    :domain,
    :data,
    :timestamp,
    :source,
    :correlation_id,
    :causation_id,
    meta: %{}
  ]

  @type kind :: :domain | :process | :ui

  @type t :: %__MODULE__{
          name: atom(),
          kind: kind(),
          domain: atom(),
          data: map(),
          timestamp: integer(),
          source: pid() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          meta: map()
        }

  @spec build(atom(), atom(), map()) :: t()
  def build(name, domain, data), do: build(name, domain, data, [])

  @spec build(atom(), atom(), map(), keyword()) :: t()
  def build(name, domain, data, opts) do
    %__MODULE__{
      name: name,
      kind: Keyword.get(opts, :kind, derive_kind(domain)),
      domain: domain,
      data: data,
      timestamp: System.monotonic_time(:millisecond),
      source: self(),
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp derive_kind(:system), do: :process
  defp derive_kind(:monitoring), do: :process
  defp derive_kind(_), do: :domain
end
