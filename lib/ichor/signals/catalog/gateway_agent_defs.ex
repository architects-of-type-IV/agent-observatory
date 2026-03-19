defmodule Ichor.Signals.Catalog.GatewayAgentDefs do
  @moduledoc false

  def definitions do
    %{
      decision_log: %{category: :gateway, keys: [:log], doc: "Inter-agent message routed"},
      schema_violation: %{
        category: :gateway,
        keys: [:event_map],
        doc: "Schema validation failure"
      },
      node_state_update: %{
        category: :gateway,
        keys: [:agent_id, :state],
        doc: "Topology node change"
      },
      entropy_alert: %{
        category: :gateway,
        keys: [:session_id, :entropy_score],
        doc: "Repeated pattern detected"
      },
      topology_snapshot: %{
        category: :gateway,
        keys: [:nodes, :edges],
        doc: "Full topology snapshot"
      },
      capability_update: %{
        category: :gateway,
        keys: [:state_map],
        doc: "Agent capability map changed"
      },
      dead_letter: %{category: :gateway, keys: [:delivery], doc: "Failed webhook to DLQ"},
      gateway_audit: %{
        category: :gateway,
        keys: [:envelope_id, :channel],
        doc: "Message routing audit"
      },
      mesh_pause: %{category: :gateway, keys: [:initiated_by], doc: "God-mode mesh pause"},
      agent_crashed: %{
        category: :agent,
        keys: [:session_id, :team_name],
        doc: "Agent confirmed dead"
      },
      nudge_warning: %{
        category: :agent,
        keys: [:session_id, :agent_name, :level],
        doc: "Nudge escalation: warn"
      },
      nudge_sent: %{
        category: :agent,
        keys: [:session_id, :agent_name, :level],
        doc: "Nudge escalation: tmux nudge sent"
      },
      nudge_escalated: %{
        category: :agent,
        keys: [:session_id, :agent_name, :level],
        doc: "Nudge escalation: HITL pause"
      },
      nudge_zombie: %{
        category: :agent,
        keys: [:session_id, :agent_name, :level],
        doc: "Nudge escalation: zombie"
      },
      agent_spawned: %{
        category: :agent,
        keys: [:session_id, :name, :capability],
        doc: "Agent spawned via dashboard"
      },
      agent_event: %{
        category: :agent,
        keys: [:event],
        dynamic: true,
        doc: "Per-agent event stream"
      },
      agent_message_intercepted: %{
        category: :agent,
        keys: [:from, :to, :content, :type],
        dynamic: true,
        doc: "Hook-intercepted SendMessage (signal only, no delivery)"
      },
      terminal_output: %{
        category: :agent,
        keys: [:session_id, :output],
        dynamic: true,
        doc: "Tmux output"
      },
      mailbox_message: %{
        category: :agent,
        keys: [:message],
        dynamic: true,
        doc: "Direct message to agent"
      },
      agent_instructions: %{
        category: :agent,
        keys: [:agent_class, :instructions],
        dynamic: true,
        doc: "Pushed instructions"
      },
      scheduled_job: %{
        category: :agent,
        keys: [:agent_id, :payload],
        dynamic: true,
        doc: "Cron job fired"
      },
      cron_job_scheduled: %{
        category: :gateway,
        keys: [:job_id, :agent_id, :next_fire_at],
        doc: "Cron job created via Ash action"
      },
      cron_job_rescheduled: %{
        category: :gateway,
        keys: [:job_id, :agent_id, :next_fire_at],
        doc: "Cron job rescheduled via Ash action"
      },
      gate_open: %{
        category: :hitl,
        keys: [:session_id],
        dynamic: true,
        doc: "Agent paused, gate opened"
      },
      gate_close: %{
        category: :hitl,
        keys: [:session_id],
        dynamic: true,
        doc: "Agent resumed, gate closed"
      },
      dag_delta: %{
        category: :mesh,
        keys: [:session_id, :added_nodes],
        dynamic: true,
        doc: "Causal DAG update"
      },
      hitl_auto_released: %{
        category: :hitl,
        keys: [:session_id],
        doc: "Paused session auto-released by sweep"
      },
      hitl_operator_approved: %{
        category: :hitl,
        keys: [:session_id],
        doc: "Operator approved buffered messages"
      },
      hitl_operator_rejected: %{
        category: :hitl,
        keys: [:session_id],
        doc: "Operator rejected buffered messages"
      }
    }
  end
end
