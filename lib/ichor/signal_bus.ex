defmodule Ichor.SignalBus do
  @moduledoc """
  Ash domain for discoverable signal-facing actions.

  The runtime facade remains `Ichor.Signals`; this domain exists so Discovery
  can enumerate mailbox and other signal actions through Ash.
  """

  use Ash.Domain, extensions: [AshAi]

  resources do
    resource(Ichor.Signals.Mailbox)
    resource(Ichor.Signals.Operations)
  end

  tools do
    tool(:check_inbox, Ichor.Signals.Operations, :check_inbox)
    tool(:acknowledge_message, Ichor.Signals.Operations, :acknowledge_message)
    tool(:send_message, Ichor.Signals.Operations, :agent_send_message)
    tool(:recent_messages, Ichor.Signals.Operations, :recent_messages)
    tool(:archon_send_message, Ichor.Signals.Operations, :operator_send_message)
    tool(:agent_events, Ichor.Signals.Operations, :agent_events)
    tool(:check_operator_inbox, Ichor.Signals.Mailbox, :check_operator_inbox)
  end
end
