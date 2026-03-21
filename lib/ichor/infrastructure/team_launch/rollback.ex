defmodule Ichor.Infrastructure.TeamLaunch.Rollback do
  @moduledoc """
  Idempotent rollback and teardown for failed or completed team launches.

  Kills the tmux session, disbands the fleet team, and removes prompt files.
  Missing sessions or directories do not raise errors.
  """

  alias Ichor.Infrastructure.FleetSupervisor
  alias Ichor.Infrastructure.Tmux.{Launcher, Script}

  @doc "Tear down a team fully, given a `TeamSpec`-like map."
  @spec teardown(map()) :: :ok
  def teardown(%{session: session, team_name: team_name, prompt_dir: prompt_dir}) do
    teardown(session, team_name, prompt_dir)
  end

  @doc "Tear down by explicit parts. Same idempotent semantics."
  @spec teardown(String.t(), String.t(), String.t() | nil) :: :ok
  def teardown(session, team_name, prompt_dir) do
    _ = Launcher.kill_session(session)
    _ = FleetSupervisor.disband_team(team_name)

    if prompt_dir do
      Script.cleanup_dir(prompt_dir)
    end

    :ok
  end
end
