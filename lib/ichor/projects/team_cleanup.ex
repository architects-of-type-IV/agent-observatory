defmodule Ichor.Projects.TeamCleanup do
  @moduledoc """
  MES-specific cleanup policy over generic lifecycle cleanup.
  """

  alias Ichor.Control.Lifecycle.Cleanup
  alias Ichor.Control.Lifecycle.TmuxLauncher
  alias Ichor.Projects.TeamSpecBuilder
  alias Ichor.Signals

  @doc "Kills a MES tmux session and cleans up associated prompt files."
  @spec kill_session(String.t()) :: :ok
  def kill_session(session) do
    Signals.emit(:mes_team_killed, %{session: session})
    _ = cleanup_module().kill_session(session)
    cleanup_prompt_files(String.replace_prefix(session, "mes-", ""))
    :ok
  end

  @doc "Cleans up prompt directories and orphaned teams from previous runs."
  @spec cleanup_old_runs() :: :ok
  def cleanup_old_runs do
    cleanup_prompt_root_dir()
    cleanup_orphaned_teams()
    :ok
  end

  @doc "Removes all subdirectories under the MES prompt root directory."
  @spec cleanup_prompt_root_dir() :: :ok
  def cleanup_prompt_root_dir do
    case File.ls(TeamSpecBuilder.prompt_root_dir()) do
      {:ok, dirs} -> Enum.each(dirs, &remove_if_directory/1)
      {:error, _} -> :ok
    end

    :ok
  end

  @doc "Removes prompt files for a specific run ID."
  @spec cleanup_prompt_files(String.t()) :: :ok
  def cleanup_prompt_files(run_id) do
    dir = TeamSpecBuilder.prompt_dir(run_id)

    if File.dir?(dir) do
      cleanup_module().cleanup_prompt_dir(dir)
      Signals.emit(:mes_cleanup, %{target: "prompt_files/#{run_id}"})
    end

    :ok
  end

  @doc "Disbands fleet teams and kills tmux sessions not backed by an active Runner."
  @spec cleanup_orphaned_teams() :: :ok
  def cleanup_orphaned_teams do
    active_teams = active_team_names()
    orphaned_teams = orphaned_team_names(active_teams, team_entries())
    orphaned_sessions = orphaned_sessions(active_teams, tmux_launcher().list_sessions())

    cleanup_module().cleanup_orphaned_teams(active_teams, "mes-")
    cleanup_module().cleanup_orphaned_tmux_sessions(active_teams, "mes-")

    Enum.each(orphaned_teams, fn name ->
      Signals.emit(:mes_cleanup, %{target: "orphaned_team/#{name}"})
    end)

    Enum.each(orphaned_sessions, fn session ->
      Signals.emit(:mes_cleanup, %{target: "orphaned_tmux/#{session}"})
    end)

    :ok
  end

  @doc "Returns a MapSet of tmux session names for all active RunProcesses."
  @spec active_team_names() :: MapSet.t(String.t())
  def active_team_names do
    run_process_module().list_all(:mes)
    |> Enum.map(fn {run_id, _pid} -> TeamSpecBuilder.session_name(run_id) end)
    |> MapSet.new()
  end

  @doc "Returns team names from fleet entries that are not in the active set."
  @spec orphaned_team_names(MapSet.t(String.t()), [{String.t(), map()}]) :: [String.t()]
  def orphaned_team_names(active_teams, team_entries) do
    team_entries
    |> Enum.map(fn {name, _meta} -> name end)
    |> Enum.filter(&String.starts_with?(&1, "mes-"))
    |> Enum.reject(&MapSet.member?(active_teams, &1))
  end

  @doc "Returns tmux session names prefixed with `mes-` that are not in the active set."
  @spec orphaned_sessions(MapSet.t(String.t()), [String.t()]) :: [String.t()]
  def orphaned_sessions(active_teams, sessions) do
    sessions
    |> Enum.filter(&String.starts_with?(&1, "mes-"))
    |> Enum.reject(&MapSet.member?(active_teams, &1))
  end

  defp remove_if_directory(dir) do
    path = Path.join(TeamSpecBuilder.prompt_root_dir(), dir)

    if File.dir?(path) do
      cleanup_module().cleanup_prompt_dir(path)
      Signals.emit(:mes_cleanup, %{target: dir})
    end
  end

  defp team_entries do
    Application.get_env(:ichor, :mes_team_supervisor_module, Ichor.Control.TeamSupervisor).list_all()
  end

  defp cleanup_module do
    Application.get_env(:ichor, :mes_cleanup_module, Cleanup)
  end

  defp tmux_launcher do
    Application.get_env(:ichor, :mes_tmux_launcher_module, TmuxLauncher)
  end

  defp run_process_module do
    Application.get_env(:ichor, :mes_run_process_module, Ichor.Projects.Runner)
  end
end
