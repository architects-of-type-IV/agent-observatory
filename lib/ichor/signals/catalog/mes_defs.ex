defmodule Ichor.Signals.Catalog.MesDefs do
  @moduledoc false

  def definitions do
    %{
      mes_scheduler_init: %{category: :mes, keys: [:paused], doc: "MES Scheduler initialized and old runs cleaned"},
      mes_scheduler_paused: %{category: :mes, keys: [:tick], doc: "MES Scheduler paused — no new teams will spawn"},
      mes_scheduler_resumed: %{category: :mes, keys: [:tick], doc: "MES Scheduler resumed — team spawning re-enabled"},
      mes_tick: %{category: :mes, keys: [:tick, :active_runs], doc: "MES Scheduler tick fired"},
      mes_cycle_started: %{category: :mes, keys: [:run_id, :team_name], doc: "MES Scheduler spawned a new manufacturing team"},
      mes_cycle_skipped: %{category: :mes, keys: [:tick, :active_runs], doc: "MES Scheduler skipped tick due to max concurrent runs"},
      mes_cycle_failed: %{category: :mes, keys: [:run_id, :reason], doc: "MES run failed to start"},
      mes_cycle_timeout: %{category: :mes, keys: [:run_id, :team_name], doc: "MES team run exceeded 10-minute budget and was killed"},
      mes_run_init: %{category: :mes, keys: [:run_id, :team_name], doc: "MES RunProcess GenServer initializing"},
      mes_run_started: %{category: :mes, keys: [:run_id, :session], doc: "MES RunProcess team spawned and kill timer armed"},
      mes_run_terminated: %{category: :mes, keys: [:run_id], doc: "MES RunProcess cleaned up on termination"},
      mes_janitor_init: %{category: :mes, keys: [:monitored], doc: "MES Janitor started, monitoring active RunProcesses"},
      mes_janitor_cleaned: %{category: :mes, keys: [:run_id, :trigger], doc: "MES Janitor cleaned up resources for a dead RunProcess"},
      mes_janitor_error: %{category: :mes, keys: [:run_id, :reason], doc: "MES Janitor encountered an error during cleanup"},
      mes_prompts_written: %{category: :mes, keys: [:run_id, :agent_count], doc: "MES agent prompt and script files written to disk"},
      mes_tmux_spawning: %{category: :mes, keys: [:session, :agent_name, :command, :tmux_args], doc: "MES about to create tmux session"},
      mes_tmux_session_created: %{category: :mes, keys: [:session, :agent_name], doc: "MES tmux session created with first agent window"},
      mes_tmux_spawn_failed: %{category: :mes, keys: [:session, :output, :exit_code], doc: "MES tmux session creation failed"},
      mes_tmux_window_created: %{category: :mes, keys: [:session, :agent_name], doc: "MES tmux window created for agent"},
      mes_team_ready: %{category: :mes, keys: [:session, :agent_count], doc: "All agents spawned in tmux session"},
      mes_team_killed: %{category: :mes, keys: [:session], doc: "MES tmux session killed"},
      mes_agent_registered: %{category: :mes, keys: [:agent_name, :session], doc: "MES agent registered in BEAM fleet"},
      mes_agent_register_failed: %{category: :mes, keys: [:agent_name, :reason], doc: "MES agent BEAM registration failed"},
      mes_team_spawn_failed: %{category: :mes, keys: [:session, :reason], doc: "MES team creation failed"},
      mes_operator_ensured: %{category: :mes, keys: [:status], doc: "MES operator AgentProcess verified or created"},
      mes_cleanup: %{category: :mes, keys: [:target], doc: "MES cleanup of old prompt dirs or sessions"},
      mes_project_created: %{category: :mes, keys: [:project_id, :title, :run_id], doc: "Coordinator submitted a completed project brief"},
      mes_project_picked_up: %{category: :mes, keys: [:project_id, :session_id], doc: "An implementation team claimed a MES project"},
      mes_subsystem_loaded: %{category: :mes, keys: [:project_id, :subsystem, :modules], doc: "Compiled subsystem hot-loaded into BEAM"},
      mes_quality_gate_passed: %{category: :mes, keys: [:run_id, :gate, :session_id], doc: "MES quality gate check passed"},
      mes_quality_gate_failed: %{category: :mes, keys: [:run_id, :gate, :session_id, :reason], doc: "MES quality gate check failed"},
      mes_quality_gate_escalated: %{category: :mes, keys: [:run_id, :gate, :failure_count], doc: "MES quality gate escalated after repeated failures"},
      mes_agent_stopped: %{category: :mes, keys: [:agent_id, :role, :team, :reason], doc: "MES agent process stopped (tmux window died or explicit stop)"},
      mes_agent_tmux_gone: %{category: :mes, keys: [:agent_id, :tmux_target], doc: "MES agent's tmux window no longer exists"},
      mes_research_ingested: %{category: :mes, keys: [:run_id, :project_id, :episode_id], doc: "Research brief ingested into the knowledge graph"},
      mes_research_ingest_failed: %{category: :mes, keys: [:run_id, :reason], doc: "Research brief ingest to knowledge graph failed"},
      mes_subsystem_compile_failed: %{category: :mes, keys: [:run_id, :project_id, :reason], doc: "Subsystem compile/load failed after DAG completion"}
    }
  end
end
