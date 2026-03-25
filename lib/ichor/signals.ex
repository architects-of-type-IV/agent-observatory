defmodule Ichor.Signals do
  @moduledoc """
  Ash domain for the ICHOR signal system.

  Owns signal resources (Operations, Checkpoint) and their Ash actions.
  Event emission uses `Ichor.Events.emit/1`.
  Event observation uses `Ichor.Events.subscribe_all/0` and `subscribe_key/1`.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Signals.Operations)
    resource(Ichor.Signals.Checkpoint)
  end

  tools do
    tool(:check_operator_inbox, Ichor.Signals.Operations, :check_operator_inbox)
    tool(:check_inbox, Ichor.Signals.Operations, :check_inbox)
    tool(:acknowledge_message, Ichor.Signals.Operations, :acknowledge_message)
    tool(:send_message, Ichor.Signals.Operations, :agent_send_message)
    tool(:recent_messages, Ichor.Signals.Operations, :recent_messages)
    tool(:archon_send_message, Ichor.Signals.Operations, :operator_send_message)
    tool(:agent_events, Ichor.Signals.Operations, :agent_events)
  end
end
