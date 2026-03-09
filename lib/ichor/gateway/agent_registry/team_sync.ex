defmodule Ichor.Gateway.AgentRegistry.TeamSync do
  @moduledoc """
  Synchronizes team membership from TeamWatcher into the ETS registry.

  Handles the complexity of merging short-name-keyed team members with
  UUID-keyed hook-registered agents, using CWD correlation via IdentityMerge.
  """

  alias Ichor.Gateway.AgentRegistry.{AgentEntry, IdentityMerge}

  @table :gateway_agent_registry

  @doc "Sync a list of teams into the ETS registry."
  @spec sync(map() | list() | term()) :: :ok
  def sync(teams) do
    teams_list = normalize(teams)
    live_team_names = teams_list |> Enum.map(& &1.name) |> MapSet.new()

    sweep_dead_teams(live_team_names)
    cwd_index = build_cwd_index()

    for team <- teams_list, member <- team.members do
      sync_member(member, team.name, cwd_index)
    end

    :ok
  end

  # ── Private ────────────────────────────────────────────────────────

  defp normalize(t) when is_map(t), do: Map.values(t)
  defp normalize(t) when is_list(t), do: t
  defp normalize(_), do: []

  defp sweep_dead_teams(live_names) do
    :ets.tab2list(@table)
    |> Enum.each(fn {session_id, agent} ->
      sweep_if_dead(agent.team, live_names, session_id)
    end)
  end

  defp sweep_if_dead(nil, _live, _sid), do: :ok

  defp sweep_if_dead(team, live_names, sid) do
    case MapSet.member?(live_names, team) do
      true -> :ok
      false -> :ets.delete(@table, sid)
    end
  end

  defp build_cwd_index do
    :ets.tab2list(@table)
    |> Enum.reduce(%{}, fn {key, agent}, acc ->
      case AgentEntry.uuid?(key) && is_nil(agent.team) && agent.status == :active && agent.cwd do
        true -> Map.update(acc, agent.cwd, [{key, agent}], &[{key, agent} | &1])
        false -> acc
      end
    end)
  end

  defp sync_member(member, team_name, cwd_index) do
    member_key = member[:agent_id] || member[:session_id]
    do_sync(member_key, member, team_name, cwd_index)
  end

  defp do_sync(nil, _member, _team_name, _index), do: :ok

  defp do_sync(member_key, member, team_name, cwd_index) do
    {canonical_key, existing} =
      IdentityMerge.find_canonical_entry(member_key, member, team_name, cwd_index)

    tmux_target = resolve_tmux_target(member[:tmux_pane_id], existing.channels.tmux)

    updated_channels =
      existing.channels
      |> Map.put(:mailbox, canonical_key)
      |> Map.put(:tmux, tmux_target)

    qualified_id = IdentityMerge.qualify_agent_id(member[:name], team_name, canonical_key)

    updated =
      existing
      |> Map.put(:id, qualified_id)
      |> Map.put(:short_name, member[:name] || existing.id)
      |> Map.put(:team, team_name)
      |> Map.put(:role, AgentEntry.role_from_string(member[:agent_type]))
      |> Map.put(:model, member[:model] || existing.model)
      |> Map.put(:cwd, member[:cwd] || existing.cwd)
      |> Map.put(:channels, updated_channels)
      |> Map.put(:status, member_status(member[:is_active]))

    :ets.insert(@table, {canonical_key, updated})
    cleanup_orphan(canonical_key, member_key)
  end

  defp member_status(true), do: :active
  defp member_status(_), do: :ended

  defp cleanup_orphan(key, key), do: :ok
  defp cleanup_orphan(_canonical, member_key), do: :ets.delete(@table, member_key)

  defp resolve_tmux_target(nil, existing), do: existing
  defp resolve_tmux_target("", existing), do: existing
  defp resolve_tmux_target(pane_id, _existing), do: pane_id
end
