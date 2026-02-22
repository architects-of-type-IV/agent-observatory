defmodule Observatory.Gateway.HITLEvents do
  @moduledoc """
  Plain structs for HITL (Human-In-The-Loop) gate events.
  """

  defmodule GateOpenEvent do
    @moduledoc false
    defstruct [:session_id, :agent_id, :operator_id, :reason, :timestamp]
  end

  defmodule GateCloseEvent do
    @moduledoc false
    defstruct [:session_id, :agent_id, :operator_id, :timestamp, :flushed_count]
  end
end
