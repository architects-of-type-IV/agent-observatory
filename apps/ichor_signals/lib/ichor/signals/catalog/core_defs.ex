defmodule Ichor.Signals.Catalog.CoreDefs do
  @moduledoc false

  def definitions do
    %{
      agent_started: %{
        category: :fleet,
        keys: [:session_id, :role, :team],
        doc: "AgentProcess init"
      },
      agent_paused: %{category: :fleet, keys: [:session_id], doc: "Agent paused via HITL"},
      agent_resumed: %{category: :fleet, keys: [:session_id], doc: "Agent resumed"},
      agent_stopped: %{
        category: :fleet,
        keys: [:session_id, :reason],
        doc: "AgentProcess terminated"
      },
      team_created: %{
        category: :fleet,
        keys: [:name, :project, :strategy],
        doc: "New team started"
      },
      team_disbanded: %{category: :fleet, keys: [:team_name], doc: "Team removed"},
      hosts_changed: %{category: :fleet, keys: [], doc: "Cluster node joined/departed"},
      fleet_changed: %{
        category: :fleet,
        keys: [:agent_id],
        doc: "Agent Registry metadata changed"
      },
      heartbeat: %{category: :system, keys: [:count], doc: "Monotonic counter every 5s"},
      registry_changed: %{category: :system, keys: [], doc: "Agent registry modified"},
      dashboard_command: %{
        category: :system,
        keys: [:command],
        doc: "External command to dashboard"
      },
      new_event: %{
        category: :events,
        keys: [:event],
        doc: "Hook event ingested by EventController"
      },
      message_delivered: %{
        category: :messages,
        keys: [:agent_id, :msg_map],
        doc: "Message delivered to agent"
      },
      block_changed: %{category: :memory, keys: [:block_id, :label], doc: "Memory block modified"},
      memory_changed: %{
        category: :memory,
        keys: [:agent_name, :event],
        dynamic: true,
        doc: "Per-agent memory change"
      }
    }
  end
end
