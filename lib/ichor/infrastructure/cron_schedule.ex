defmodule Ichor.Infrastructure.CronSchedule do
  @moduledoc """
  Schedule math helpers for the cron system.

  Centralises time arithmetic so that `CronScheduler` callbacks stay
  declarative and the recurrence model is easy to adjust in isolation.
  """

  @doc """
  Compute the `DateTime` at which a one-time job should fire, given a delay
  in milliseconds from now.

  The result is truncated to seconds so it stores cleanly in the database.
  """
  @spec next_fire_at(pos_integer()) :: DateTime.t()
  def next_fire_at(delay_ms) when is_integer(delay_ms) and delay_ms > 0 do
    DateTime.utc_now()
    |> DateTime.add(delay_ms, :millisecond)
    |> DateTime.truncate(:second)
  end

  @doc """
  Compute the next fire time for a recurring job, given the fixed
  recurrence interval in milliseconds.
  """
  @spec next_recurrence(pos_integer()) :: DateTime.t()
  def next_recurrence(interval_ms \\ 60_000) when is_integer(interval_ms) and interval_ms > 0 do
    next_fire_at(interval_ms)
  end

  @doc """
  Compute the delay (in milliseconds) from now until `fire_at`.

  Returns at least `0` so `Process.send_after/3` never receives a negative
  value for a job that is already overdue.
  """
  @spec delay_until(DateTime.t()) :: non_neg_integer()
  def delay_until(%DateTime{} = fire_at) do
    max(DateTime.diff(fire_at, DateTime.utc_now(), :millisecond), 0)
  end

  @doc """
  Validate that `delay_ms` is a positive integer suitable for scheduling.

  Returns `:ok` or `{:error, :invalid_delay}`.
  """
  @spec validate_delay(term()) :: :ok | {:error, :invalid_delay}
  def validate_delay(delay_ms) when is_integer(delay_ms) and delay_ms > 0, do: :ok
  def validate_delay(_), do: {:error, :invalid_delay}
end
