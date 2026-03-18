defmodule Ichor.Signals.Catalog.TeamMonitoringDefs do
  @moduledoc false

  def definitions do
    %{
      task_created: %{category: :team, keys: [:task], dynamic: true, doc: "New task added"},
      task_updated: %{category: :team, keys: [:task], dynamic: true, doc: "Task status changed"},
      task_deleted: %{category: :team, keys: [:task_id], dynamic: true, doc: "Task removed"},
      tasks_updated: %{category: :team, keys: [:team_name], doc: "Team task list changed"},
      protocol_update: %{
        category: :monitoring,
        keys: [:stats_map],
        doc: "Protocol stats recomputed"
      },
      gate_passed: %{
        category: :monitoring,
        keys: [:session_id, :task_id],
        doc: "Quality gate passed"
      },
      gate_failed: %{
        category: :monitoring,
        keys: [:session_id, :task_id, :output],
        doc: "Quality gate failed"
      },
      agent_done: %{
        category: :monitoring,
        keys: [:session_id, :summary],
        doc: "Agent signalled DONE"
      },
      agent_blocked: %{
        category: :monitoring,
        keys: [:session_id, :reason],
        doc: "Agent signalled BLOCKED"
      },
      swarm_state: %{category: :monitoring, keys: [:state_map], doc: "Swarm pipeline recomputed"},
      watchdog_sweep: %{
        category: :monitoring,
        keys: [:orphaned_count],
        doc: "TeamWatchdog periodic sweep completed"
      }
    }
  end
end
