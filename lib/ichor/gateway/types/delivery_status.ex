defmodule Ichor.Gateway.Types.DeliveryStatus do
  @moduledoc """
  Ash enum type for webhook delivery lifecycle status.

  - `:pending`   -- queued, not yet attempted
  - `:delivered` -- successfully delivered
  - `:failed`    -- attempted but failed, scheduled for retry
  - `:dead`      -- exceeded max attempts, moved to dead-letter queue
  """

  use Ash.Type.Enum, values: [:pending, :delivered, :failed, :dead]
end
