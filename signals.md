Ichor Signals Convention

Purpose

This document defines a maintainable Pub/Sub convention for a large Ash + Phoenix + Elixir application using a central Ash Domain named Ichor.Signals.

The goal is to keep signaling:
	•	predictable
	•	easy to refactor
	•	easy to reason about
	•	decoupled from raw Phoenix PubSub usage
	•	decoupled from raw Ash notification payload shapes

This convention treats Ichor.Signals as a signal protocol layer, not as a second business domain model.

⸻

Core Idea

Use:
	•	one central signal layer
	•	one stable message envelope
	•	one central topic builder
	•	one publish/subscribe API
	•	one Ash-to-signal translation layer
	•	optional thin helper modules per business domain

Do not use:
	•	raw topic strings across the app
	•	raw Phoenix.PubSub.broadcast/3 all over the app
	•	one Elixir module per signal/event by default
	•	raw Ash notification payloads as app-wide contracts
	•	a giant Ichor.Signals bucket containing business logic from every domain

⸻

Design Principles

1. Centralize the bus, not the business

Ichor.Signals owns:
	•	signal transport
	•	message envelope
	•	topic naming
	•	publish/subscribe API
	•	Ash notification translation

Business domains still own business meaning.

Examples:
	•	Ichor.Billing owns billing semantics
	•	Ichor.Accounts owns account semantics
	•	Ichor.Workflows owns workflow semantics

2. Use one message shape everywhere

The app should not pass around ad hoc maps with inconsistent keys.

Every published signal should have the same envelope.

3. Treat domain + resource + action as the event identity

The durable identity of a signal is not a dedicated module name.

The durable identity is the tuple:
	•	kind
	•	domain
	•	resource
	•	action

Example:
	•	:domain, :billing, :invoice, :paid
	•	:process, :workflows, :workflow, :progressed
	•	:ui, :billing, :invoice, :refresh_requested

4. Keep payloads as normalized maps by default

Do not create one struct module per signal unless the signal is genuinely special.

The default payload shape belongs in the data field of the message envelope.

5. Keep Ash-specific shapes at the edge

Ash notifications should be translated into the Ichor.Signals shape before the rest of the app sees them.

This keeps the signaling contract stable even if Ash notification details change.

⸻

Recommended Folder Layout

lib/ichor/
  signals/
    signals.ex
    bus.ex
    message.ex
    topics.ex
    from_ash.ex

  billing/
    signals.ex

  accounts/
    signals.ex

  workflows/
    signals.ex

This is the lean default.

Split further only when the code actually needs it.

⸻

Core Modules

Ichor.Signals.Message

This is the single message envelope used by the app.

defmodule Ichor.Signals.Message do
  @enforce_keys [:kind, :topic, :domain, :resource, :action, :data]
  defstruct [
    :kind,
    :topic,
    :domain,
    :resource,
    :action,
    :data,
    :tenant_id,
    :actor_id,
    :correlation_id,
    :causation_id,
    :timestamp,
    meta: %{}
  ]

  @type kind :: :domain | :process | :ui

  @type t :: %__MODULE__{
          kind: kind(),
          topic: String.t(),
          domain: atom(),
          resource: atom(),
          action: atom(),
          data: map(),
          tenant_id: term() | nil,
          actor_id: term() | nil,
          correlation_id: String.t() | nil,
          causation_id: String.t() | nil,
          timestamp: DateTime.t() | nil,
          meta: map()
        }
end

Notes
	•	kind separates domain, process, and UI signals.
	•	topic is the Pub/Sub topic.
	•	domain, resource, and action identify the signal.
	•	data holds the normalized payload.
	•	meta holds extra optional metadata.

⸻

Ichor.Signals.Topics

This is the single place where topic strings are built.

defmodule Ichor.Signals.Topics do
  @spec entity(atom(), atom(), term()) :: String.t()
  def entity(domain, resource, id) do
    "#{domain}:#{resource}:#{id}"
  end

  @spec collection(atom(), atom()) :: String.t()
  def collection(domain, resource) do
    "#{domain}:#{resource}"
  end

  @spec tenant(atom(), term()) :: String.t()
  def tenant(domain, tenant_id) do
    "#{domain}:tenant:#{tenant_id}"
  end

  @spec process(term()) :: String.t()
  def process(id) do
    "process:#{id}"
  end

  @spec ui(String.t()) :: String.t()
  def ui(name) do
    "ui:#{name}"
  end
end

Notes
	•	No raw topic strings outside this module.
	•	Topic naming should stay boring and predictable.
	•	Do not optimize for cleverness.

⸻

Ichor.Signals.Bus

This module is the only place that talks directly to Phoenix.PubSub.

defmodule Ichor.Signals.Bus do
  alias Phoenix.PubSub

  @pubsub Ichor.PubSub

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: PubSub.subscribe(@pubsub, topic)

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: PubSub.unsubscribe(@pubsub, topic)

  @spec broadcast(Ichor.Signals.Message.t()) :: :ok | {:error, term()}
  def broadcast(%Ichor.Signals.Message{topic: topic} = message) do
    PubSub.broadcast(@pubsub, topic, message)
  end
end

Notes
	•	This keeps the transport boundary centralized.
	•	If instrumentation, tracing, or logging is added later, this is the place.

⸻

Ichor.Signals

This is the public API for creating and publishing messages.

defmodule Ichor.Signals do
  alias Ichor.Signals.Bus
  alias Ichor.Signals.Message

  @spec subscribe(String.t()) :: :ok | {:error, term()}
  def subscribe(topic), do: Bus.subscribe(topic)

  @spec unsubscribe(String.t()) :: :ok
  def unsubscribe(topic), do: Bus.unsubscribe(topic)

  @spec publish(Message.t()) :: :ok | {:error, term()}
  def publish(%Message{} = message) do
    message
    |> put_timestamp()
    |> Bus.broadcast()
  end

  @spec new_message(
          Message.kind(),
          String.t(),
          atom(),
          atom(),
          atom(),
          map(),
          keyword()
        ) :: Message.t()
  def new_message(kind, topic, domain, resource, action, data, opts \\ []) do
    %Message{
      kind: kind,
      topic: topic,
      domain: domain,
      resource: resource,
      action: action,
      data: data,
      tenant_id: Keyword.get(opts, :tenant_id),
      actor_id: Keyword.get(opts, :actor_id),
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id),
      timestamp: Keyword.get(opts, :timestamp),
      meta: Keyword.get(opts, :meta, %{})
    }
  end

  defp put_timestamp(%Message{timestamp: nil} = message) do
    %{message | timestamp: DateTime.utc_now()}
  end

  defp put_timestamp(%Message{} = message), do: message
end

Notes
	•	One obvious public entrypoint reduces drift.
	•	All published signals should flow through this API.

⸻

Domain Helper Modules

These modules are optional.

They exist only to remove duplication when the same signal construction appears in multiple places.

They should stay small.

They should not become a second event framework.

Ichor.Billing.Signals

defmodule Ichor.Billing.Signals do
  alias Ichor.Signals
  alias Ichor.Signals.Topics

  @spec invoice_paid(map(), keyword()) :: :ok | {:error, term()}
  def invoice_paid(invoice, opts \\ []) do
    topic = Topics.entity(:billing, :invoice, invoice.id)

    data = %{
      id: invoice.id,
      tenant_id: invoice.tenant_id,
      amount: invoice.amount,
      paid_at: invoice.paid_at
    }

    Signals.new_message(
      :domain,
      topic,
      :billing,
      :invoice,
      :paid,
      data,
      tenant_id: invoice.tenant_id,
      actor_id: Keyword.get(opts, :actor_id),
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id),
      meta: Keyword.get(opts, :meta, %{})
    )
    |> Signals.publish()
  end

  @spec invoice_updated(map(), keyword()) :: :ok | {:error, term()}
  def invoice_updated(invoice, opts \\ []) do
    topic = Topics.entity(:billing, :invoice, invoice.id)

    data = %{
      id: invoice.id,
      tenant_id: invoice.tenant_id,
      status: invoice.status,
      updated_at: invoice.updated_at
    }

    Signals.new_message(
      :domain,
      topic,
      :billing,
      :invoice,
      :updated,
      data,
      tenant_id: invoice.tenant_id,
      actor_id: Keyword.get(opts, :actor_id),
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id),
      meta: Keyword.get(opts, :meta, %{})
    )
    |> Signals.publish()
  end
end

Notes
	•	Business semantics stay in the business domain.
	•	Signal construction is reduced to a thin helper layer.
	•	No dedicated InvoicePaid module is needed.

⸻

Ichor.Workflows.Signals

defmodule Ichor.Workflows.Signals do
  alias Ichor.Signals
  alias Ichor.Signals.Topics

  @spec progressed(term(), atom(), atom(), keyword()) :: :ok | {:error, term()}
  def progressed(workflow_id, step, status, opts \\ []) do
    topic = Topics.process(workflow_id)

    data = %{
      workflow_id: workflow_id,
      step: step,
      status: status
    }

    Signals.new_message(
      :process,
      topic,
      :workflows,
      :workflow,
      :progressed,
      data,
      correlation_id: Keyword.get(opts, :correlation_id),
      causation_id: Keyword.get(opts, :causation_id),
      meta: Keyword.get(opts, :meta, %{})
    )
    |> Signals.publish()
  end
end

Notes
	•	Process signals are not resource lifecycle signals.
	•	They should still use the same envelope and transport.

⸻

Ash Integration

Ash notifications are one source of signals.

They are not the signal protocol itself.

The rest of the app should not depend directly on raw Ash notification payload shapes.

Ichor.Signals.FromAsh

defmodule Ichor.Signals.FromAsh do
  alias Ichor.Billing.Signals, as: BillingSignals

  @spec publish(term()) :: :ok
  def publish(notification) do
    case notification do
      %{resource: Ichor.Billing.Invoice, action: %{name: :pay}, data: invoice} ->
        BillingSignals.invoice_paid(
          invoice,
          actor_id: actor_id(notification),
          correlation_id: correlation_id(notification),
          causation_id: causation_id(notification)
        )

      %{resource: Ichor.Billing.Invoice, action: %{name: :update}, data: invoice} ->
        BillingSignals.invoice_updated(
          invoice,
          actor_id: actor_id(notification),
          correlation_id: correlation_id(notification),
          causation_id: causation_id(notification)
        )

      _other ->
        :ok
    end
  end

  defp actor_id(notification) do
    get_in(notification, [:context, :actor, :id])
  end

  defp correlation_id(notification) do
    get_in(notification, [:context, :shared, :correlation_id])
  end

  defp causation_id(notification) do
    get_in(notification, [:context, :shared, :causation_id])
  end
end

Notes
	•	This module translates Ash shapes into app-level signal shapes.
	•	Keep this module dumb and explicit.
	•	It is an adapter, not a logic hub.

⸻

Consumer Example

LiveView subscription and handling

defmodule IchorWeb.InvoiceLive.Show do
  use IchorWeb, :live_view

  alias Ichor.Signals
  alias Ichor.Signals.Message
  alias Ichor.Signals.Topics

  def mount(%{"id" => id}, _session, socket) do
    if connected?(socket) do
      :ok = Signals.subscribe(Topics.entity(:billing, :invoice, id))
    end

    {:ok, assign(socket, invoice_id: id)}
  end

  def handle_info(
        %Message{
          domain: :billing,
          resource: :invoice,
          action: :paid,
          data: %{id: invoice_id}
        },
        socket
      ) do
    {:noreply, put_flash(socket, :info, "Invoice #{invoice_id} paid")}
  end

  def handle_info(
        %Message{
          domain: :billing,
          resource: :invoice,
          action: :updated
        },
        socket
      ) do
    {:noreply, socket}
  end

  def handle_info(_message, socket), do: {:noreply, socket}
end

Notes
	•	Consumers match on the stable message envelope.
	•	They do not depend on raw Ash notification payloads.
	•	Topic building remains centralized.

⸻

What Scales in This Model

This model scales because:
	•	there is one message shape
	•	there is one topic naming system
	•	event identity is kind + domain + resource + action
	•	payloads are normalized maps
	•	helper modules are optional and thin
	•	Ash integration stays at the edge
	•	business meaning stays in business domains

This gives enough structure without creating module explosion.

⸻

Rules

Rule 1

Only Ichor.Signals.Topics builds topic strings.

Rule 2

Only Ichor.Signals.Bus talks directly to Phoenix.PubSub.

Rule 3

All published signals must use Ichor.Signals.Message.

Rule 4

Signal identity is always:
	•	kind
	•	domain
	•	resource
	•	action

Rule 5

Payload goes in data as a normalized map.

Rule 6

Ash notifications are translated in Ichor.Signals.FromAsh.

They are not the app-wide contract.

Rule 7

Use domain helper modules like Ichor.Billing.Signals only when they remove duplication.

Rule 8

Do not create dedicated event modules unless the event is truly special.

Rule 9

Do not let LiveViews, workers, or services invent topic names locally.

Rule 10

Keep Ichor.Signals as a protocol layer.

Do not let it absorb business logic from every domain.

⸻

What Not To Do

Do not:
	•	hardcode topic strings across the app
	•	call Phoenix.PubSub.broadcast/3 from random modules
	•	make one module per signal by default
	•	expose raw Ash notification payloads to the rest of the system
	•	mix domain, process, and UI signals without a clear kind
	•	treat meta as a dumping ground for unstructured data
	•	turn Ichor.Signals into a giant event swamp

⸻

Mental Model

Ichor.Signals is:
	•	a protocol layer
	•	a transport boundary
	•	a naming convention
	•	a stable envelope contract

Ichor.Signals is not:
	•	a second business domain model
	•	a full event sourcing framework
	•	a module-per-event hierarchy
	•	the owner of all business semantics

The short version is:

Centralize the bus, not the business.

Use one signal envelope.

Use one topic builder.

Treat kind + domain + resource + action as the stable identity.

Keep Ash-specific shapes at the edge.

That is the maintainable version.
