defmodule Ichor.Projects.Runner.Modes do
  @moduledoc """
  Returns `Runner.Mode` configuration structs for each run kind.

  Each mode encodes the data-driven differences between MES, Genesis, and
  DAG runners: which signals to subscribe to, what timers to schedule,
  when to consider a run complete, and how to clean up.
  """

  alias Ichor.Projects.Runner.{Hooks, Mode}

  @liveness_ms :timer.seconds(30)
  @liveness_dag_ms :timer.seconds(60)
  @deadline_ms :timer.minutes(10)
  @stale_check_ms :timer.seconds(60)
  @health_check_ms :timer.seconds(30)

  @doc "Returns the Mode config struct for the given kind."
  @spec config(:mes | :genesis | :dag, String.t(), keyword()) :: Mode.t()
  def config(:mes, run_id, opts) do
    team_name = Keyword.get(opts, :team_name, "mes-#{run_id}")

    %Mode{
      kind: :mes,
      subscriptions: [:mes],
      timers: %{
        liveness_ms: @liveness_ms,
        deadline_ms: @deadline_ms,
        on_init: &Hooks.MES.on_init/1
      },
      completion: %{
        source: :signal,
        signal: :mes_project_created
      },
      checks: nil,
      cleanup: %{policy: :mes_janitor},
      signals: %{
        ready: :mes_run_started,
        completed: :mes_run_complete,
        tmux_gone: :mes_tmux_gone,
        terminated: :mes_run_terminated,
        deadline_reached: :mes_deadline_reached
      },
      commands: nil,
      hooks: %{
        on_signal: &Hooks.MES.on_signal/2,
        on_complete: fn state ->
          Ichor.Signals.emit(:mes_run_complete, %{
            run_id: state.run_id,
            session: state.session
          })
        end,
        team_name: team_name
      }
    }
  end

  def config(:genesis, _run_id, opts) do
    mode_label = Keyword.get(opts, :mode, "unknown")

    %Mode{
      kind: :genesis,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &genesis_coordinator_id/1
      },
      checks: nil,
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :genesis_run_init,
        completed: :genesis_run_complete,
        tmux_gone: :genesis_tmux_gone,
        terminated: :genesis_run_terminated
      },
      commands: nil,
      hooks: %{
        on_complete: fn state ->
          Ichor.Signals.emit(:genesis_run_complete, %{
            run_id: state.run_id,
            mode: mode_label,
            session: state.session,
            delivered_by: "operator"
          })
        end
      }
    }
  end

  def config(:dag, _run_id, _opts) do
    %Mode{
      kind: :dag,
      subscriptions: [:messages],
      timers: %{liveness_ms: @liveness_dag_ms},
      completion: %{
        source: :message_delivered,
        coordinator_id_fn: &dag_coordinator_id/1
      },
      checks: [
        %{id: :stale, every_ms: @stale_check_ms, callback: &Hooks.DAG.check_stale/1},
        %{id: :health, every_ms: @health_check_ms, callback: &Hooks.DAG.check_health/1}
      ],
      cleanup: %{policy: :teardown},
      signals: %{
        ready: :dag_run_ready,
        completed: :dag_run_completed,
        tmux_gone: :dag_tmux_gone,
        terminated: :dag_run_terminated
      },
      commands: %{
        sync_job: &Hooks.DAG.sync_job/2
      },
      hooks: %{
        on_complete: &Hooks.DAG.on_complete/1
      }
    }
  end

  # ---------------------------------------------------------------------------
  # Coordinator ID helpers
  # ---------------------------------------------------------------------------

  defp genesis_coordinator_id(%{session: session}), do: session

  defp dag_coordinator_id(%{session: session}), do: "#{session}-coordinator"
end
