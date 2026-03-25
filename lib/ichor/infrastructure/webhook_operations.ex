defmodule Ichor.Infrastructure.WebhookOperations do
  @moduledoc """
  Ash resource wrapping the WebhookAdapter as generic actions.

  Provides a domain-level, policy-ready, code_interface-callable surface for
  webhook delivery operations. The underlying WebhookAdapter is not modified.
  """

  use Ash.Resource, domain: Ichor.Infrastructure

  alias Ichor.Infrastructure.WebhookAdapter

  code_interface do
    define(:deliver, args: [:url, :payload])
    define(:verify_signature, args: [:payload, :secret, :signature])
  end

  actions do
    action :deliver, :map do
      description("Deliver a payload to a webhook URL via Oban-backed durable delivery.")

      argument(:url, :string, allow_nil?: false)
      argument(:payload, :map, allow_nil?: false)

      run(fn input, _context ->
        case WebhookAdapter.deliver(input.arguments.url, input.arguments.payload) do
          {:ok, delivery_id} -> {:ok, %{"delivery_id" => delivery_id, "status" => "enqueued"}}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :verify_signature, :boolean do
      description("Verify that a provided signature matches the HMAC for the given payload and secret.")

      argument(:payload, :string, allow_nil?: false)
      argument(:secret, :string, allow_nil?: false)
      argument(:signature, :string, allow_nil?: false)

      run(fn input, _context ->
        {:ok,
         WebhookAdapter.verify_signature(
           input.arguments.payload,
           input.arguments.secret,
           input.arguments.signature
         )}
      end)
    end
  end
end
