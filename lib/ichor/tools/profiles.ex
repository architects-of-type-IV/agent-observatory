defmodule Ichor.Tools.Profiles do
  @moduledoc """
  Tool exposure profiles for MCP endpoints.

  Each profile returns a list of tool atoms that should be
  available to that actor type via the MCP router.
  """

  @doc "Tools available to spawned agents via /mcp endpoint."
  @spec agent() :: [atom()]
  def agent do
    [
      # Messaging
      :check_inbox,
      :acknowledge_message,
      :send_message,
      # Tasks
      :get_tasks,
      :update_task_status,
      # Spawning
      :spawn_agent,
      :stop_agent,
      # Memory
      :list_agents,
      :create_agent,
      :read_memory,
      :memory_replace,
      :memory_insert,
      :memory_rethink,
      :conversation_search,
      :conversation_search_date,
      :archival_memory_insert,
      :archival_memory_search,
      # Project planning
      :create_project_draft,
      :advance_project,
      :list_project_overviews,
      :get_project_overview,
      :gate_check,
      :create_adr,
      :update_adr,
      :list_adrs,
      :create_feature,
      :list_features,
      :create_use_case,
      :list_use_cases,
      :create_checkpoint,
      :create_conversation,
      :list_conversations,
      :create_phase,
      :create_section,
      :create_task,
      :create_subtask,
      :list_phases,
      # DAG execution
      :next_tasks,
      :claim_task,
      :complete_task,
      :fail_task,
      :get_run_status,
      :load_jsonl,
      :export_jsonl
    ]
  end

  @doc "Tools available to the Archon via /mcp/archon endpoint."
  @spec archon() :: [atom()]
  def archon do
    [
      # Fleet observation
      :list_archon_agents,
      :agent_status,
      # Fleet control
      :spawn_archon_agent,
      :stop_archon_agent,
      :pause_agent,
      :resume_agent,
      :sweep,
      # Teams
      :list_teams,
      # Messaging
      :archon_send_message,
      :recent_messages,
      # System
      :system_health,
      :tmux_sessions,
      # Manager
      :manager_snapshot,
      :attention_queue,
      # Events
      :agent_events,
      :fleet_tasks,
      # Knowledge graph
      :search_memory,
      :remember,
      :query_memory,
      # MES
      :list_projects,
      :create_project,
      :check_operator_inbox,
      :mes_status,
      :cleanup_mes
    ]
  end
end
