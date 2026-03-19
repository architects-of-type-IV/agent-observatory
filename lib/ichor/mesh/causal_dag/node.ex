defmodule Ichor.Mesh.CausalDAG.Node do
  @moduledoc false

  @enforce_keys [
    :trace_id,
    :agent_id,
    :intent,
    :confidence_score,
    :entropy_score,
    :action_status,
    :timestamp
  ]
  defstruct trace_id: nil,
            parent_step_id: nil,
            agent_id: nil,
            intent: nil,
            confidence_score: nil,
            entropy_score: nil,
            action_status: nil,
            timestamp: nil,
            children: [],
            orphan: false

  @type t :: %__MODULE__{
          trace_id: String.t(),
          parent_step_id: String.t() | nil,
          agent_id: String.t(),
          intent: atom() | String.t(),
          confidence_score: float(),
          entropy_score: float(),
          action_status: atom() | String.t(),
          timestamp: DateTime.t(),
          children: [String.t()],
          orphan: boolean()
        }
end
