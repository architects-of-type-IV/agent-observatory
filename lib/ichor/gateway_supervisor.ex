defmodule Ichor.GatewaySupervisor do
  @moduledoc """
  Supervises gateway services: entropy tracker, heartbeat manager,
  cron scheduler, webhook router, and HITL relay.

  Uses one_for_one: services are independent. Agent lifecycle is owned by
  Ichor.Registry (via FleetSupervisor/TeamSupervisor), not this supervisor.
  """
  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(_opts) do
    children = [
      {Ichor.Gateway.TmuxDiscovery, []},
      {Ichor.Gateway.EntropyTracker, []},
      {Ichor.Gateway.HeartbeatManager, []},
      {Ichor.Gateway.CronScheduler, []},
      {Ichor.Gateway.WebhookRouter, []},
      {Ichor.Gateway.HITLRelay, []},
      {Ichor.Gateway.OutputCapture, []}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
