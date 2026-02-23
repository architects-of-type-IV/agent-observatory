defmodule Observatory.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      # Infrastructure (must start first -- everything depends on these)
      ObservatoryWeb.Telemetry,
      Observatory.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:observatory, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:observatory, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Observatory.PubSub},

      # Core services (mailbox, command queue, teams, notes, janitor, memory)
      Observatory.CoreSupervisor,

      # Gateway services (rest_for_one: registry first, then downstream)
      Observatory.GatewaySupervisor,

      # Mesh/DAG services (rest_for_one: DAG first, then topology + event bridge)
      Observatory.MeshSupervisor,

      # Monitoring services (independent observers)
      Observatory.MonitorSupervisor,

      # Web endpoint (must start last -- depends on all services above)
      ObservatoryWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Observatory.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    ObservatoryWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
