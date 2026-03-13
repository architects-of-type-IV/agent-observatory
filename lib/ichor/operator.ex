defmodule Ichor.Operator do
  @moduledoc """
  Unified operator messaging interface.

  Two delivery paths:
    1. BEAM-native: AgentProcess.send_message (GenServer.cast)
    2. Tmux direct: Registry metadata lookup -> Tmux.deliver

  Targets:
    - `"agent:<session_id>"` or `"session:<session_id>"` -- single agent
    - `"team:<name>"` -- all members of a team
    - `"fleet:all"` -- all active agents
    - raw session_id string -- treated as agent target
  """

  alias Ichor.Fleet.{AgentProcess, TeamSupervisor}
  alias Ichor.Gateway.Channels.Tmux

  @from "operator"
  @type_iv_registry Ichor.Registry

  @doc """
  Spawn a new agent in a tmux session with instruction overlay.

  Delegates to AgentSpawner. Returns `{:ok, agent_info}` or `{:error, reason}`.
  """
  defdelegate spawn_agent(opts), to: Ichor.AgentSpawner

  @doc """
  Stop a spawned agent by session name.
  """
  defdelegate stop_agent(session_name), to: Ichor.AgentSpawner

  @doc """
  Send a message to any target. Returns `{:ok, delivered_count}` or `{:error, reason}`.

  Uses BEAM-native AgentProcess delivery. Falls back to direct tmux delivery
  via Registry metadata when no BEAM process exists.
  """
  def send(target, content, opts \\ []) when is_binary(target) and is_binary(content) do
    channel = normalize_target(target)

    payload = %{
      content: content,
      from: @from,
      type: Keyword.get(opts, :type, :text),
      metadata: Keyword.get(opts, :metadata, %{})
    }

    case channel do
      "team:" <> name -> deliver_to_team(name, payload)
      "fleet:all" -> deliver_to_fleet(payload)
      _ -> deliver_to_agent(extract_id(channel), payload)
    end
  end

  # ── Delivery ──────────────────────────────────────────────────────────

  defp deliver_to_agent(id, payload) do
    if AgentProcess.alive?(id) do
      AgentProcess.send_message(id, payload)
      {:ok, 1}
    else
      # Fallback: direct tmux using Registry metadata
      case Registry.lookup(@type_iv_registry, {:agent, id}) do
        [{_pid, %{tmux_target: target}}] when is_binary(target) ->
          Tmux.deliver(target, payload)
          {:ok, 1}

        _ ->
          {:ok, 0}
      end
    end
  end

  defp deliver_to_team(name, payload) do
    if TeamSupervisor.exists?(name) do
      ids = TeamSupervisor.member_ids(name)
      Enum.each(ids, &AgentProcess.send_message(&1, payload))
      {:ok, length(ids)}
    else
      {:ok, 0}
    end
  end

  defp deliver_to_fleet(payload) do
    agents = AgentProcess.list_all()
    Enum.each(agents, fn {id, _meta} -> AgentProcess.send_message(id, payload) end)
    {:ok, length(agents)}
  end

  # ── Target Normalization ──────────────────────────────────────────────

  defp extract_id("agent:" <> id), do: id
  defp extract_id("session:" <> id), do: id
  defp extract_id("member:" <> id), do: id
  defp extract_id("role:" <> id), do: id
  defp extract_id(raw), do: raw

  defp normalize_target("agent:" <> _ = channel), do: channel
  defp normalize_target("session:" <> _ = channel), do: channel
  defp normalize_target("team:" <> _ = channel), do: channel
  defp normalize_target("fleet:" <> _ = channel), do: channel
  defp normalize_target("role:" <> _ = channel), do: channel
  defp normalize_target("all"), do: "fleet:all"
  defp normalize_target("all_teams"), do: "fleet:all"
  defp normalize_target("lead:" <> _name), do: "role:lead"
  defp normalize_target("member:" <> sid), do: "session:#{sid}"
  defp normalize_target(id), do: "agent:#{id}"
end
