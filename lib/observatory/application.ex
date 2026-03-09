defmodule Observatory.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    ensure_tmux_server()

    children = [
      # Infrastructure (must start first -- everything depends on these)
      ObservatoryWeb.Telemetry,
      Observatory.Repo,
      {Ecto.Migrator,
       repos: Application.fetch_env!(:observatory, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:observatory, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Observatory.PubSub},

      # BEAM-native fleet registries (must start before FleetSupervisor)
      {Registry, keys: :unique, name: Observatory.Fleet.ProcessRegistry},
      {Registry, keys: :unique, name: Observatory.Fleet.TeamRegistry},

      # :pg scope for cluster-wide process discovery
      %{id: :pg_observatory_agents, start: {:pg, :start_link, [:observatory_agents]}},

      # Fleet host registry (tracks BEAM nodes in the cluster)
      Observatory.Fleet.HostRegistry,

      # Core services (mailbox, command queue, teams, notes, janitor, memory)
      Observatory.CoreSupervisor,

      # Gateway services (rest_for_one: registry first, then downstream)
      Observatory.GatewaySupervisor,

      # Fleet supervisor (BEAM-native teams + agents, after Gateway for channel access)
      Observatory.Fleet.FleetSupervisor,

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

  @observatory_socket Path.expand("~/.observatory/tmux/obs.sock")

  defp ensure_tmux_server do
    socket_dir = Path.dirname(@observatory_socket)
    File.mkdir_p!(socket_dir)

    case System.cmd("tmux", ["-S", @observatory_socket, "list-sessions"], stderr_to_stdout: true) do
      {_, 0} ->
        :ok

      _ ->
        System.cmd("tmux", ["-S", @observatory_socket, "new-session", "-d", "-s", "obs"],
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
