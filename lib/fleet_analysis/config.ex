defmodule FleetAnalysis.Config do
  @moduledoc """
  Thresholds for `FleetAnalysis`.

  All of these are judgement calls about what "unhealthy" means, and the right
  numbers depend on what your agents do. An agent that runs long builds is
  legitimately silent for minutes; one that should be replying to messages is
  not. Tune accordingly.

      config :fleet_analysis,
        stuck_after_sec: 60,
        idle_after_sec: 120,
        loop_window: 5,
        loop_min_repeats: 3,
        failure_rate_warning: 0.3,
        failure_rate_critical: 0.5
  """

  @defaults %{
    stuck_after_sec: 60,
    idle_after_sec: 120,
    loop_window: 5,
    loop_min_repeats: 3,
    failure_rate_warning: 0.3,
    failure_rate_critical: 0.5
  }

  @doc "Seconds of silence after which an agent counts as stuck."
  @spec stuck_after_sec() :: pos_integer()
  def stuck_after_sec, do: get(:stuck_after_sec)

  @doc "Seconds of silence after which a session is rendered as idle rather than active."
  @spec idle_after_sec() :: pos_integer()
  def idle_after_sec, do: get(:idle_after_sec)

  @doc "How many recent events loop detection looks back over."
  @spec loop_window() :: pos_integer()
  def loop_window, do: get(:loop_window)

  @doc "How many consecutive identical tool calls count as a loop."
  @spec loop_min_repeats() :: pos_integer()
  def loop_min_repeats, do: get(:loop_min_repeats)

  @doc "Failure rate above which health degrades to `:warning`."
  @spec failure_rate_warning() :: float()
  def failure_rate_warning, do: get(:failure_rate_warning)

  @doc "Failure rate above which a `:high_failure_rate` issue is raised."
  @spec failure_rate_critical() :: float()
  def failure_rate_critical, do: get(:failure_rate_critical)

  defp get(key), do: Application.get_env(:fleet_analysis, key, Map.fetch!(@defaults, key))
end
