defmodule Ichor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_tmux_server()
    Ichor.AgentSpawner.init_counter()

    children = [
      # Infrastructure (must start first -- everything depends on these)
      IchorWeb.Telemetry,
      Ichor.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ichor, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ichor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ichor.PubSub},

      # BEAM-native fleet registries (must start before FleetSupervisor)
      {Registry, keys: :unique, name: Ichor.Fleet.ProcessRegistry},
      {Registry, keys: :unique, name: Ichor.Fleet.TeamRegistry},

      # :pg scope for cluster-wide process discovery
      %{id: :pg_ichor_agents, start: {:pg, :start_link, [:ichor_agents]}},

      # Fleet host registry (tracks BEAM nodes in the cluster)
      Ichor.Fleet.HostRegistry,

      # Core services (mailbox, command queue, teams, notes, janitor, memory)
      Ichor.CoreSupervisor,

      # Gateway services (rest_for_one: registry first, then downstream)
      Ichor.GatewaySupervisor,

      # Fleet supervisor (BEAM-native teams + agents, after Gateway for channel access)
      Ichor.Fleet.FleetSupervisor,

      # Mesh/DAG services (rest_for_one: DAG first, then topology + event bridge)
      Ichor.MeshSupervisor,

      # Monitoring services (independent observers)
      Ichor.MonitorSupervisor,

      # Web endpoint (must start last -- depends on all services above)
      IchorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Ichor.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    IchorWeb.Endpoint.config_change(changed, removed)
    :ok
  end

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")

  defp ensure_tmux_server do
    socket_dir = Path.dirname(@ichor_socket)
    File.mkdir_p!(socket_dir)

    case System.cmd("tmux", ["-S", @ichor_socket, "list-sessions"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      _ ->
        System.cmd("tmux", ["-S", @ichor_socket, "new-session", "-d", "-s", "obs"],
          stderr_to_stdout: true
        )

        :ok
    end
  end

  defp skip_migrations?() do
    # By default, sqlite migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
