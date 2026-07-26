defmodule CronScheduler.Schedule do
  @moduledoc """
  Pure schedule arithmetic.

  No store, no queue, no clock injection — just the conversions between delays
  and absolute fire times. Kept separate so the timing rules are testable on
  their own.

  Fire times are truncated to the second, because most stores (and cron-style
  queues) have second granularity anyway and keeping microseconds around only
  produces round-trip surprises.
  """

  @doc """
  Absolute fire time `delay_ms` from now, truncated to the second.

      iex> fire_at = CronScheduler.Schedule.next_fire_at(60_000)
      iex> DateTime.diff(fire_at, DateTime.utc_now()) in 58..60
      true
  """
  @spec next_fire_at(pos_integer()) :: DateTime.t()
  def next_fire_at(delay_ms) when is_integer(delay_ms) and delay_ms > 0 do
    DateTime.utc_now()
    |> DateTime.add(delay_ms, :millisecond)
    |> DateTime.truncate(:second)
  end

  @doc """
  Milliseconds from now until `fire_at`, clamped at zero.

  A job whose time has already passed returns `0` rather than a negative delay,
  so recovery after downtime fires it immediately instead of erroring.

      iex> CronScheduler.Schedule.delay_until(DateTime.add(DateTime.utc_now(), -60))
      0
  """
  @spec delay_until(DateTime.t()) :: non_neg_integer()
  def delay_until(%DateTime{} = fire_at) do
    max(DateTime.diff(fire_at, DateTime.utc_now(), :millisecond), 0)
  end

  @doc """
  Milliseconds converted to whole seconds, rounded up.

  Queues schedule in seconds. Rounding down would fire a sub-second delay
  immediately, so anything above zero gets at least one second.

      iex> CronScheduler.Schedule.to_seconds(1)
      1
      iex> CronScheduler.Schedule.to_seconds(0)
      0
      iex> CronScheduler.Schedule.to_seconds(2_500)
      3
  """
  @spec to_seconds(non_neg_integer()) :: non_neg_integer()
  def to_seconds(0), do: 0
  def to_seconds(ms) when is_integer(ms) and ms > 0, do: ceil(ms / 1000)

  @doc """
  Validate a delay.

      iex> CronScheduler.Schedule.validate_delay(1_000)
      :ok
      iex> CronScheduler.Schedule.validate_delay(0)
      {:error, :invalid_delay}
      iex> CronScheduler.Schedule.validate_delay("soon")
      {:error, :invalid_delay}
  """
  @spec validate_delay(term()) :: :ok | {:error, :invalid_delay}
  def validate_delay(delay_ms) when is_integer(delay_ms) and delay_ms > 0, do: :ok
  def validate_delay(_), do: {:error, :invalid_delay}
end
