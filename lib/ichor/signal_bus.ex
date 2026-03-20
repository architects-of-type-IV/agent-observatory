defmodule Ichor.SignalBus do
  @moduledoc """
  Ash domain for discoverable signal-facing actions.

  The runtime facade remains `Ichor.Signals`; this domain exists so Discovery
  can enumerate mailbox and other signal actions through Ash.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Signals.Mailbox)
  end
end
