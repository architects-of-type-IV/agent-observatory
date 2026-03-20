defmodule Ichor.Control do
  @moduledoc """
  Ash Domain: control-plane infrastructure.

  Holds integration resources that support the runtime but are not part of the
  canonical Workshop modeling surface.
  """
  use Ash.Domain

  resources do
    resource(Ichor.Gateway.WebhookDelivery)
    resource(Ichor.Gateway.CronJob)
  end
end
