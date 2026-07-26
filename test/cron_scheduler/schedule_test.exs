defmodule CronScheduler.ScheduleTest do
  use ExUnit.Case, async: true

  alias CronScheduler.Schedule

  doctest CronScheduler.Schedule

  describe "next_fire_at/1" do
    test "returns a time the given delay into the future" do
      fire_at = Schedule.next_fire_at(60_000)

      assert DateTime.diff(fire_at, DateTime.utc_now()) in 58..60
    end

    test "truncates to the second" do
      assert Schedule.next_fire_at(1_000).microsecond == {0, 0}
    end
  end

  describe "delay_until/1" do
    test "returns the remaining milliseconds" do
      future = DateTime.add(DateTime.utc_now(), 60, :second)

      assert Schedule.delay_until(future) in 59_000..60_000
    end

    test "clamps a past time to zero rather than going negative" do
      past = DateTime.add(DateTime.utc_now(), -3_600, :second)

      assert Schedule.delay_until(past) == 0
    end
  end

  describe "to_seconds/1" do
    test "rounds up so a sub-second delay does not collapse to immediate" do
      assert Schedule.to_seconds(1) == 1
      assert Schedule.to_seconds(999) == 1
      assert Schedule.to_seconds(1_001) == 2
    end

    test "keeps zero as zero" do
      assert Schedule.to_seconds(0) == 0
    end

    test "converts whole seconds exactly" do
      assert Schedule.to_seconds(5_000) == 5
    end
  end

  describe "validate_delay/1" do
    test "accepts a positive integer" do
      assert Schedule.validate_delay(1) == :ok
      assert Schedule.validate_delay(60_000) == :ok
    end

    test "rejects zero, negatives, and non-integers" do
      assert Schedule.validate_delay(0) == {:error, :invalid_delay}
      assert Schedule.validate_delay(-1) == {:error, :invalid_delay}
      assert Schedule.validate_delay(1.5) == {:error, :invalid_delay}
      assert Schedule.validate_delay("soon") == {:error, :invalid_delay}
      assert Schedule.validate_delay(nil) == {:error, :invalid_delay}
    end
  end
end
