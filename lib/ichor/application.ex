defmodule Ichor.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  alias Ichor.Infrastructure.AgentLaunch
  alias Ichor.Infrastructure.CronScheduler
  alias Ichor.Notes
  alias Ichor.Signals.Bus

  @impl true
  def start(_type, _args) do
    AgentLaunch.init_counter()
    Bus.start_message_log()
    Notes.init()

    children = [
      # Infrastructure (must start first -- everything depends on these)
      IchorWeb.Telemetry,
      Ichor.Repo,
      {Oban, Application.fetch_env!(:ichor, Oban)},
      {Ecto.Migrator,
       repos: Application.fetch_env!(:ichor, :ecto_repos), skip: skip_migrations?()},
      {DNSCluster, query: Application.get_env(:ichor, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: Ichor.PubSub},

      # Single BEAM-native registry for all process types (must start before FleetSupervisor)
      {Registry, keys: :unique, name: Ichor.Registry},

      # :pg scope for cluster-wide process discovery
      %{id: :pg_ichor_agents, start: {:pg, :start_link, [:ichor_agents]}},

      # Fleet host registry (tracks BEAM nodes in the cluster)
      Ichor.Infrastructure.HostRegistry,

      # Task supervisor for fire-and-forget tasks (must start before RuntimeSupervisor and
      # FleetSupervisor -- OutputCapture and AgentProcess both call Ichor.TaskSupervisor)
      {Task.Supervisor, name: Ichor.TaskSupervisor},

      # Runtime services (shared infrastructure, monitoring, and signal-adjacent processes)
      Ichor.RuntimeSupervisor,

      # Fleet supervisor (BEAM-native teams + agents, after Gateway for channel access)
      Ichor.Fleet.Supervisor,

      # Projectors: react to Signals-originated events and perform side effects
      Ichor.Projector.FleetLifecycle,
      Ichor.Projector.CleanupDispatcher,

      # Factory planning and pipeline lifecycle
      Ichor.Factory.LifecycleSupervisor,

      # Projectors: signal subscribers for MES project/research ingestion and run completion
      # (independent of BuildRunSupervisor -- no causal dependency, so not nested inside
      # LifecycleSupervisor)
      Ichor.Projector.MesProjectIngestor,
      Ichor.Projector.MesResearchIngestor,
      Ichor.Factory.CompletionHandler,

      # Workshop runtime launch listener (signal-driven team spawns)
      # NOTE: TeamSpawnHandler is a projector/signal subscriber; future step is to group it
      # with the projectors above under a dedicated Projectors.Supervisor.
      Ichor.Workshop.TeamSpawnHandler,

      # Planning runs
      {DynamicSupervisor, name: Ichor.Factory.PlanRunSupervisor, strategy: :one_for_one},

      # Pipeline execution runs
      {DynamicSupervisor, name: Ichor.Factory.PipelineRunSupervisor, strategy: :one_for_one},

      # Web endpoint (must start last -- depends on all services above)
      IchorWeb.Endpoint
    ]

    opts = [strategy: :one_for_one, name: Ichor.Supervisor]
    result = Supervisor.start_link(children, opts)

    # Non-blocking post-startup tasks -- must not block or crash the supervision tree
    Task.start(fn ->
      try do
        ensure_tmux_server()
        CronScheduler.recover_jobs()
      rescue
        _ -> :ok
      end
    end)

    result
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

  defp skip_migrations? do
    # By default, migrations are run when using a release
    System.get_env("RELEASE_NAME") == nil
  end
end
