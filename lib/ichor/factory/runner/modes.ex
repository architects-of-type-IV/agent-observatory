defmodule Ichor.Factory.Runner.Modes do
  @moduledoc """
  Pure `%Runner.Mode{}` struct factories.

  Builds data-driven mode configuration for MES, planning, and pipeline runs.
  Hook function slots that require GenServer-private callbacks are left as `nil`
  and must be filled in by the caller (Runner) via the `runner_hooks` argument.

  ## Runner hooks keys

  - `:mes_on_init`       — `fn state -> ... end` called after timers are scheduled
  - `:mes_on_signal`     — `fn msg, state -> state end` for MES signal dispatch
  - `:pipeline_check_stale`  — `fn state -> :ok end` periodic stale-task check
  - `:pipeline_check_health` — `fn state -> :ok end` periodic health-report check
  - `:pipeline_sync_task`    — `fn state, task -> {:noreply, state} end`
  - `:pipeline_on_complete`  — `fn state -> :ok end`
  """

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Factory.{Runner.Mode, RunRef}

  @doc """
  Builds the `%Mode{}` configuration struct for the given `kind`.

  `runner_hooks` is a map of atom keys to function values for slots that
  Runner must supply (private GenServer callbacks). Any key absent from the
  map defaults to `nil`.
  """
  @spec build(:mes | :planning | :pipeline, String.t(), keyword(), map()) :: Mode.t()
  def build(kind, run_id, opts, runner_hooks \\ %{})

  def build(:mes, run_id, opts, runner_hooks) do
    team_name = Keyword.get(opts, :team_name, RunRef.session_name(RunRef.new(:mes, run_id)))

    %Mode{
      kind: :mes,
      subscriptions: [:mes, :messages],
      timers: %{
        liveness_ms: runner_timer(:liveness_ms),
        deadline_ms: runner_timer(:deadline_ms),
        on_init: Map.get(runner_hooks, :mes_on_init)
      },
      completion: %{
        source: :signal_or_message,
        signal: :mes_project_created,
        coordinator_id_fn: fn %{session: session} -> "#{session}-coordinator" end
      },
      checks: nil,
      cleanup: %{policy: :signal},
      signals: %{
        ready: :mes_run_started,
        completed: :run_complete,
        tmux_gone: :mes_tmux_gone,
        terminated: :mes_run_terminated,
        deadline_reached: :mes_deadline_reached
      },
      commands: nil,
      hooks: %{
        on_signal: Map.get(runner_hooks, :mes_on_signal),
        on_complete: fn state ->
          Events.emit(
            Event.new(
              "fleet.run.complete",
              state.run_id,
              %{kind: :mes, run_id: state.run_id, session: state.session},
              %{legacy_name: :run_complete}
            )
          )
        end,
        team_name: team_name
      }
    }
  end

  def build(:planning, _run_id, opts, _runner_hooks) do
    mode_label = Keyword.get(opts, :mode, "unknown")

    %Mode{
      kind: :planning,
      subscriptions: [:messages],
      timers: %{liveness_ms: runner_timer(:liveness_ms)},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &planning_coordinator_id/1
      },
      checks: nil,
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :planning_run_init,
        completed: :planning_run_complete,
        tmux_gone: :planning_tmux_gone,
        terminated: :planning_run_terminated
      },
      commands: nil,
      hooks: %{
        on_complete: fn state ->
          Events.emit(
            Event.new(
              "planning.run.complete",
              state.run_id,
              %{
                run_id: state.run_id,
                mode: mode_label,
                session: state.session,
                delivered_by: "operator"
              },
              %{legacy_name: :planning_run_complete}
            )
          )
        end
      }
    }
  end

  def build(:pipeline, _run_id, _opts, runner_hooks) do
    %Mode{
      kind: :pipeline,
      subscriptions: [:messages],
      timers: %{liveness_ms: runner_timer(:liveness_pipeline_ms)},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &pipeline_coordinator_id/1
      },
      checks: [
        %{
          id: :stale,
          every_ms: runner_timer(:stale_check_ms),
          callback: Map.get(runner_hooks, :pipeline_check_stale)
        },
        %{
          id: :health,
          every_ms: runner_timer(:health_check_ms),
          callback: Map.get(runner_hooks, :pipeline_check_health)
        }
      ],
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :pipeline_ready,
        completed: :pipeline_completed,
        tmux_gone: :pipeline_tmux_gone,
        terminated: :pipeline_terminated
      },
      commands: %{
        sync_task: Map.get(runner_hooks, :pipeline_sync_task)
      },
      hooks: %{
        on_complete: Map.get(runner_hooks, :pipeline_on_complete)
      }
    }
  end

  defp planning_coordinator_id(%{session: session}), do: session
  defp pipeline_coordinator_id(%{session: session}), do: "#{session}-coordinator"

  # Timer constants are owned by Runner and sourced via application config so
  # that tests can override them. We re-read from the compile-time Runner
  # constants via module attribute delegation.
  defp runner_timer(:liveness_ms), do: :timer.seconds(30)
  defp runner_timer(:liveness_pipeline_ms), do: :timer.seconds(60)
  defp runner_timer(:deadline_ms), do: :timer.minutes(10)
  defp runner_timer(:stale_check_ms), do: :timer.seconds(60)
  defp runner_timer(:health_check_ms), do: :timer.seconds(30)
end
