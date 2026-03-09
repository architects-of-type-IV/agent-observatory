defmodule Ichor.GatewaySupervisor do
  @moduledoc """
  Supervises gateway services: agent registry, entropy tracker, capability map,
  heartbeat manager, cron scheduler, webhook router, and HITL relay.

  Uses rest_for_one: AgentRegistry must start first. If it crashes, all downstream
  gateway services restart in order (they depend on the registry for routing).
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Ichor.Gateway.AgentRegistry, []},
      {Ichor.Gateway.TmuxDiscovery, []},
      {Ichor.Gateway.EntropyTracker, []},
      {Ichor.Gateway.CapabilityMap, []},
      {Ichor.Gateway.HeartbeatManager, []},
      {Ichor.Gateway.CronScheduler, []},
      {Ichor.Gateway.WebhookRouter, []},
      {Ichor.Gateway.HITLRelay, []},
      {Ichor.Gateway.OutputCapture, []}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
