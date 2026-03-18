defmodule Ichor.Repo.Migrations.CreateDagRunsAndJobs do
  use Ecto.Migration

  def up do
    execute("""
    CREATE TABLE dag_runs (
      id TEXT PRIMARY KEY,
      label TEXT NOT NULL,
      source TEXT NOT NULL DEFAULT 'imported',
      node_id TEXT,
      project_path TEXT,
      tmux_session TEXT,
      status TEXT NOT NULL DEFAULT 'active',
      job_count INTEGER NOT NULL DEFAULT 0,
      inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now'))
    )
    """)

    execute("CREATE INDEX idx_dag_runs_status ON dag_runs(status)")
    execute("CREATE INDEX idx_dag_runs_node_id ON dag_runs(node_id)")

    execute("""
    CREATE TABLE dag_jobs (
      id TEXT PRIMARY KEY,
      run_id TEXT NOT NULL REFERENCES dag_runs(id) ON DELETE CASCADE,
      external_id TEXT NOT NULL,
      subtask_id TEXT,
      subject TEXT NOT NULL,
      description TEXT,
      goal TEXT,
      allowed_files TEXT NOT NULL DEFAULT '[]',
      steps TEXT NOT NULL DEFAULT '[]',
      done_when TEXT,
      blocked_by TEXT NOT NULL DEFAULT '[]',
      status TEXT NOT NULL DEFAULT 'pending',
      owner TEXT,
      priority TEXT NOT NULL DEFAULT 'medium',
      wave INTEGER,
      acceptance_criteria TEXT NOT NULL DEFAULT '[]',
      phase_label TEXT,
      tags TEXT NOT NULL DEFAULT '[]',
      notes TEXT,
      claimed_at TEXT,
      completed_at TEXT,
      inserted_at TEXT NOT NULL DEFAULT (datetime('now')),
      updated_at TEXT NOT NULL DEFAULT (datetime('now')),
      UNIQUE(run_id, external_id)
    )
    """)

    execute("CREATE INDEX idx_dag_jobs_run_status ON dag_jobs(run_id, status)")
    execute("CREATE INDEX idx_dag_jobs_run_wave ON dag_jobs(run_id, wave)")
  end

  def down do
    execute("DROP TABLE IF EXISTS dag_jobs")
    execute("DROP TABLE IF EXISTS dag_runs")
  end
end
