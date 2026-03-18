defmodule Ichor.Signals.Catalog.GenesisDagDefs do
  @moduledoc false

  def definitions do
    %{
      genesis_team_ready: %{
        category: :genesis,
        keys: [:session, :mode, :project_id, :genesis_node_id, :agent_count],
        doc: "Genesis mode team spawned and ready in tmux"
      },
      genesis_team_spawn_failed: %{category: :genesis, keys: [:session, :reason], doc: "Genesis mode team failed to spawn"},
      genesis_team_killed: %{category: :genesis, keys: [:session], doc: "Genesis tmux session killed during cleanup"},
      genesis_run_init: %{category: :genesis, keys: [:run_id, :mode, :session], doc: "RunProcess started monitoring a genesis mode run"},
      genesis_tmux_gone: %{category: :genesis, keys: [:run_id, :session], doc: "Genesis tmux session no longer exists (liveness check)"},
      genesis_run_complete: %{category: :genesis, keys: [:run_id, :mode, :session, :delivered_by], doc: "Genesis mode run completed (coordinator delivered to operator)"},
      genesis_run_terminated: %{category: :genesis, keys: [:run_id, :mode], doc: "RunProcess GenServer terminated"},
      genesis_artifact_created: %{
        category: :genesis,
        keys: [:id, :node_id, :type],
        doc: "Genesis artifact created via MCP tool (ADR, Feature, UseCase, Checkpoint, etc.)"
      },
      dag_run_created: %{category: :dag, keys: [:run_id, :source, :label, :job_count], doc: "Dag.Run created (genesis or imported ingest)"},
      dag_run_ready: %{category: :dag, keys: [:run_id, :session, :node_id], doc: "Dag.Run spawned with lead agent in tmux"},
      dag_run_completed: %{category: :dag, keys: [:run_id, :label], doc: "All jobs completed for a run"},
      dag_job_claimed: %{category: :dag, keys: [:run_id, :external_id, :owner, :wave], doc: "Job claimed by a lead agent"},
      dag_job_completed: %{category: :dag, keys: [:run_id, :external_id, :owner], doc: "Job marked completed after verification"},
      dag_job_failed: %{category: :dag, keys: [:run_id, :external_id, :notes], doc: "Job marked failed"},
      dag_job_reset: %{category: :dag, keys: [:run_id, :external_id], doc: "Stale or failed job reset to pending"},
      dag_tmux_gone: %{category: :dag, keys: [:run_id, :session], doc: "DAG tmux session no longer exists (liveness check)"},
      dag_health_report: %{category: :dag, keys: [:run_id, :healthy, :issue_count], doc: "Periodic health check result for a run"},
      dag_run_archived: %{category: :dag, keys: [:run_id, :label, :reason], doc: "DAG run archived by watchdog after unexpected death"}
    }
  end
end
