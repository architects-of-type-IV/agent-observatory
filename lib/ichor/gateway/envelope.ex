defmodule Ichor.Gateway.Envelope do
  @moduledoc """
  Normalized message envelope for the Gateway pipeline.
  All messages flowing through Gateway.Router are wrapped in this struct.
  """

  @enforce_keys [:channel, :payload]
  defstruct [
    :id,
    :channel,
    :payload,
    :from,
    :timestamp,
    :trace_id
  ]

  @type t :: %__MODULE__{
          id: String.t() | nil,
          channel: String.t(),
          payload: map(),
          from: String.t() | nil,
          timestamp: DateTime.t() | nil,
          trace_id: String.t() | nil
        }

  @doc "Build an envelope with auto-generated id and timestamp."
  def new(channel, payload, opts \\ []) do
    %__MODULE__{
      id: generate_id(),
      channel: channel,
      payload: payload,
      from: Keyword.get(opts, :from),
      timestamp: DateTime.utc_now(),
      trace_id: Keyword.get(opts, :trace_id, generate_id())
    }
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
