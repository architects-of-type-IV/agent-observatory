defmodule Observatory.Gateway.AgentRegistry.IdentityMerge do
  @moduledoc """
  Correlates agent identities across naming schemes.

  Team members are registered by short name (from TeamWatcher config),
  while hook events register by UUID session ID. This module merges
  these into a single canonical entry by CWD correlation.
  """

  @table :gateway_agent_registry

  # ── Qualified ID ───────────────────────────────────────────────────

  @doc "Build a qualified agent ID like `name@team`, disambiguating collisions."
  @spec qualify_agent_id(String.t() | nil, String.t(), String.t()) :: String.t() | nil
  def qualify_agent_id(nil, _team_name, _session_id), do: nil

  def qualify_agent_id(name, team_name, session_id) do
    base_id = "#{name}@#{team_name}"

    case collision?(base_id, session_id) do
      true -> "#{name}-#{String.slice(session_id, 0, 4)}@#{team_name}"
      false -> base_id
    end
  end

  # ── Canonical Entry Resolution ─────────────────────────────────────

  @doc """
  Find the canonical ETS entry for a team member. Prefers UUID-keyed entries
  (from hook events) over short-name-keyed entries (from TeamWatcher config).
  Correlation: match by cwd among unaffiliated (team-less) active agents.
  """
  @spec find_canonical_entry(String.t(), map(), String.t(), map()) :: {String.t(), map()}
  def find_canonical_entry(member_key, member, team_name, unaffiliated_by_cwd) do
    case lookup(member_key) do
      %{team: ^team_name} = existing ->
        {member_key, existing}

      _ ->
        case correlate_by_cwd(member[:cwd], unaffiliated_by_cwd) do
          {uuid_key, uuid_agent} ->
            {uuid_key, uuid_agent}

          nil ->
            existing = lookup(member_key) || default_agent(member_key)
            {member_key, existing}
        end
    end
  end

  # ── Team Entry Absorption ──────────────────────────────────────────

  @doc """
  When a hook event registers a UUID-keyed agent, check if there's an orphaned
  team-registered entry (short-name key) with matching cwd. If so, absorb its
  team metadata and delete the orphan.
  """
  @spec maybe_absorb_team_entry(String.t(), map()) :: map()
  def maybe_absorb_team_entry(uuid_key, agent) do
    case absorbable?(uuid_key, agent) do
      false ->
        agent

      true ->
        case find_orphan(agent.cwd) do
          {orphan_key, orphan_agent} ->
            :ets.delete(@table, orphan_key)
            absorb(agent, orphan_agent)

          nil ->
            agent
        end
    end
  rescue
    ArgumentError -> agent
  end

  # ── Channel Merge ──────────────────────────────────────────────────

  @doc "Merge channels from hook and team entries, preferring team tmux and hook mailbox."
  @spec merge_channels(map(), map()) :: map()
  def merge_channels(hook_channels, team_channels) do
    %{
      tmux: team_channels.tmux || hook_channels.tmux,
      mailbox: hook_channels.mailbox || team_channels.mailbox,
      webhook: hook_channels.webhook || team_channels.webhook
    }
  end

  # ── Utilities ──────────────────────────────────────────────────────

  @doc "Check if a string is a valid UUID."
  @spec uuid?(String.t()) :: boolean()
  def uuid?(str) when is_binary(str), do: match?({:ok, _}, Ecto.UUID.cast(str))
  def uuid?(_), do: false

  # ── Private ────────────────────────────────────────────────────────

  defp collision?(base_id, session_id) do
    :ets.tab2list(@table)
    |> Enum.any?(fn {sid, a} -> a.id == base_id && sid != session_id end)
  rescue
    ArgumentError -> false
  end

  defp correlate_by_cwd(nil, _index), do: nil

  defp correlate_by_cwd(cwd, index) do
    case Map.get(index, cwd, []) do
      [{key, agent}] -> {key, agent}
      _ -> nil
    end
  end

  defp absorbable?(uuid_key, agent) do
    uuid?(uuid_key) && is_nil(agent.team) && agent.cwd != nil
  end

  defp find_orphan(cwd) do
    :ets.match_object(@table, {:_, %{cwd: cwd}})
    |> Enum.find(fn {key, a} ->
      not uuid?(key) && a.team != nil && key != "operator"
    end)
  end

  defp absorb(agent, orphan) do
    agent
    |> Map.put(:id, orphan.id)
    |> Map.put(:short_name, orphan.short_name)
    |> Map.put(:team, orphan.team)
    |> Map.put(:role, orphan.role)
    |> Map.merge(%{channels: merge_channels(agent.channels, orphan.channels)})
  end

  defp lookup(session_id) do
    case :ets.lookup(@table, session_id) do
      [{^session_id, agent}] -> agent
      [] -> nil
    end
  rescue
    ArgumentError -> nil
  end

  defp default_agent(session_id) do
    short = String.slice(session_id, 0, 8)

    %{
      id: short,
      short_name: short,
      session_id: session_id,
      host: "local",
      parent_id: nil,
      team: nil,
      role: :standalone,
      status: :active,
      model: nil,
      cwd: nil,
      current_tool: nil,
      started_at: DateTime.utc_now(),
      last_event_at: DateTime.utc_now(),
      channels: %{tmux: nil, ssh_tmux: nil, mailbox: session_id, webhook: nil}
    }
  end
end
