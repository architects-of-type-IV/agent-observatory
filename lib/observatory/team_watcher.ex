defmodule Observatory.TeamWatcher do
  @moduledoc """
  Watches ~/.claude/teams/ and ~/.claude/tasks/ directories for active team state.
  Polls periodically and broadcasts changes via PubSub.
  """
  use GenServer
  require Logger

  @poll_interval 2_000

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  def get_state, do: GenServer.call(__MODULE__, :get_state)

  @impl true
  def init(_opts) do
    claude_dir = Path.join(System.user_home!(), ".claude")

    state = %{
      teams_dir: Path.join(claude_dir, "teams"),
      tasks_dir: Path.join(claude_dir, "tasks"),
      teams: %{}
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state.teams, state}
  end

  @impl true
  def handle_info(:poll, state) do
    Process.send_after(self(), :poll, @poll_interval)
    teams = scan_teams(state.teams_dir, state.tasks_dir)

    if teams != state.teams do
      Phoenix.PubSub.broadcast(
        Observatory.PubSub,
        "teams:update",
        {:teams_updated, teams}
      )
    end

    {:noreply, %{state | teams: teams}}
  end

  defp scan_teams(teams_dir, tasks_dir) do
    teams_from_dirs(teams_dir, tasks_dir)
    |> Map.merge(teams_from_files(teams_dir, tasks_dir))
  end

  # Pattern: ~/.claude/teams/{name}/config.json (directory-based)
  defp teams_from_dirs(teams_dir, tasks_dir) do
    with {:ok, entries} <- File.ls(teams_dir) do
      entries
      |> Enum.map(fn name ->
        config_path = Path.join([teams_dir, name, "config.json"])
        read_team_config(name, config_path, tasks_dir)
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new(fn t -> {t.name, t} end)
    else
      _ -> %{}
    end
  end

  # Pattern: ~/.claude/teams/{name}.json (flat file)
  defp teams_from_files(teams_dir, tasks_dir) do
    with {:ok, entries} <- File.ls(teams_dir) do
      entries
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn filename ->
        name = String.trim_trailing(filename, ".json")
        config_path = Path.join(teams_dir, filename)
        read_team_config(name, config_path, tasks_dir)
      end)
      |> Enum.reject(&is_nil/1)
      |> Map.new(fn t -> {t.name, t} end)
    else
      _ -> %{}
    end
  end

  defp read_team_config(name, config_path, tasks_dir) do
    with {:ok, json} <- File.read(config_path),
         {:ok, config} <- Jason.decode(json) do
      tasks = read_tasks(tasks_dir, name)

      %{
        name: name,
        members: parse_members(config["members"] || []),
        tasks: tasks,
        description: config["description"]
      }
    else
      _ -> nil
    end
  end

  defp parse_members(members) when is_list(members) do
    Enum.map(members, fn m ->
      %{
        name: m["name"],
        agent_id: m["agentId"],
        agent_type: m["agentType"]
      }
    end)
  end

  defp parse_members(_), do: []

  defp read_tasks(tasks_dir, team_name) do
    path = Path.join(tasks_dir, team_name)

    with {:ok, files} <- File.ls(path) do
      files
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn f ->
        with {:ok, json} <- File.read(Path.join(path, f)),
             {:ok, task} <- Jason.decode(json) do
          %{
            id: task["id"],
            subject: task["subject"],
            description: task["description"],
            status: task["status"] || "pending",
            owner: task["owner"],
            blocked_by: task["blockedBy"] || [],
            blocks: task["blocks"] || [],
            active_form: task["activeForm"]
          }
        else
          _ -> nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      _ -> []
    end
  end
end
