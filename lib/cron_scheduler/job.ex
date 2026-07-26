defmodule CronScheduler.Job do
  @moduledoc """
  A scheduled job.

  The unit both the store and the queue deal in. `payload` is an opaque string —
  the scheduler encodes terms to JSON on the way in and hands the string back
  untouched on fire, so the store never has to understand what it carries.

  A one-time job is deleted once it fires; a recurring job is rescheduled
  `interval_ms` into the future and re-enqueued.
  """

  @enforce_keys [:id, :agent_id, :payload, :next_fire_at]
  defstruct [
    :id,
    :agent_id,
    :payload,
    :next_fire_at,
    :inserted_at,
    :interval_ms,
    is_one_time: true
  ]

  @type t :: %__MODULE__{
          id: String.t(),
          agent_id: String.t(),
          payload: String.t(),
          next_fire_at: DateTime.t(),
          inserted_at: DateTime.t() | nil,
          interval_ms: pos_integer() | nil,
          is_one_time: boolean()
        }

  @doc """
  Build a job, generating an id and `inserted_at` when they are not supplied.

  Stores that assign their own ids (a database default, say) should pass `:id`
  explicitly.
  """
  @spec new(map() | keyword()) :: t()
  def new(attrs) do
    attrs = Map.new(attrs)

    %__MODULE__{
      id: Map.get(attrs, :id) || generate_id(),
      agent_id: Map.fetch!(attrs, :agent_id),
      payload: Map.fetch!(attrs, :payload),
      next_fire_at: Map.fetch!(attrs, :next_fire_at),
      inserted_at: Map.get(attrs, :inserted_at) || DateTime.truncate(DateTime.utc_now(), :second),
      interval_ms: Map.get(attrs, :interval_ms),
      is_one_time: Map.get(attrs, :is_one_time, true)
    }
  end

  defp generate_id, do: :crypto.strong_rand_bytes(16) |> Base.encode16(case: :lower)
end
