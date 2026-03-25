defmodule Ichor.Events do
  @moduledoc """
  Ash domain for durable event storage.

  Exposes the append-only stored event log for replay, audit, and projection rebuilds.
  """

  use Ash.Domain

  resources do
    resource(Ichor.Events.StoredEvent)
  end
end
