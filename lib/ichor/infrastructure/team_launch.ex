defmodule Ichor.Infrastructure.TeamLaunch do
  @moduledoc """
  Lifecycle operations for launching and tearing down multi-agent tmux-backed teams.

  Orchestrates the named launch stages:
    1. `TeamLaunch.Scripts`      — write prompt and script files
    2. `TeamLaunch.Session`      — create tmux session and windows
    3. `TeamLaunch.Registration` — register agents in the fleet registry

  On failure, `TeamLaunch.Rollback` cleans up any partially-created resources.
  """

  alias Ichor.Infrastructure.TeamSpec
  alias Ichor.Infrastructure.TeamLaunch.{Registration, Rollback, Scripts, Session}

  @doc "Launch a full multi-agent team: creates tmux session, all windows, and registers all agents."
  @spec launch(TeamSpec.t()) :: {:ok, String.t()} | {:error, term()}
  def launch(%TeamSpec{} = spec) do
    with {:error, reason} <- do_launch(spec) do
      Rollback.teardown(spec)
      {:error, reason}
    end
  end

  defp do_launch(%TeamSpec{} = spec) do
    with {:ok, scripts} <- Scripts.write_all(spec),
         :ok <- Session.create_all(spec, scripts),
         :ok <- Registration.register_all(spec) do
      {:ok, spec.session}
    end
  end

  @doc "Launch a single agent from the spec into an already-running tmux session."
  @spec launch_into_existing_session(TeamSpec.t(), String.t()) :: :ok | {:error, term()}
  def launch_into_existing_session(%TeamSpec{agents: [agent]} = spec, session) do
    with {:ok, scripts} <- Scripts.write_all(spec),
         :ok <- Session.create_window(session, spec.cwd, agent, scripts),
         {:ok, _result} <- Registration.register_one(agent, session) do
      :ok
    end
  end

  @doc """
  Tear down a launched team: kill the tmux session, disband the fleet team,
  and remove prompt files. Idempotent -- missing session or prompt dir does not raise.
  """
  @spec teardown(TeamSpec.t()) :: :ok
  def teardown(%TeamSpec{} = spec), do: Rollback.teardown(spec)

  @doc "Tear down by explicit parts rather than a spec struct. Same idempotent semantics."
  @spec teardown(String.t(), String.t(), String.t() | nil) :: :ok
  def teardown(session, team_name, prompt_dir), do: Rollback.teardown(session, team_name, prompt_dir)
end
