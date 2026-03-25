defmodule Ichor.Fleet.AgentRegistryProjection do
  @moduledoc """
  Builds and derives registry metadata for agent processes.

  The registry entry is the primary projection of agent state used by the
  dashboard, observers, and other fleet consumers.  Keeping projection logic
  here keeps it testable in isolation and decoupled from GenServer callbacks.
  """

  @type_iv_registry Ichor.Registry

  @doc """
  Build the initial registry metadata map when an agent process starts.

  `id` and `state` come from the freshly-initialised `AgentProcess` struct;
  `meta` is the raw keyword/map of extra options passed at startup.
  """
  @spec build_initial(String.t(), map(), map()) :: map()
  def build_initial(id, state, meta) do
    tmux_target = extract_tmux_target(state.backend)
    tmux_session = extract_session_name(tmux_target)
    short_name = meta[:short_name] || meta[:name] || id

    %{
      role: state.role,
      team: state.team,
      status: :active,
      model: meta[:model],
      cwd: meta[:cwd],
      current_tool: nil,
      channels: meta[:channels] || %{tmux: tmux_target, mailbox: id, webhook: nil},
      os_pid: meta[:os_pid],
      last_event_at: meta[:last_event_at] || DateTime.utc_now(),
      short_name: short_name,
      name: meta[:name] || id,
      host: meta[:host] || "local",
      parent_id: meta[:parent_id],
      backend_type: backend_type(state.backend),
      tmux_session: tmux_session,
      tmux_target: tmux_target
    }
  end

  @doc """
  Derive registry field updates from an incoming agent event.

  Always sets `last_event_at` and marks the agent `:active`.  Merges in any
  relevant event fields (`model`, `cwd`, `os_pid`, `current_tool`).
  """
  @spec fields_from_event(map()) :: map()
  def fields_from_event(event) do
    %{last_event_at: DateTime.utc_now(), status: :active}
    |> maybe_put(:model, Map.get(event, :model_name))
    |> maybe_put(:cwd, Map.get(event, :cwd))
    |> maybe_put(:os_pid, Map.get(event, :os_pid))
    |> merge_current_tool(event)
  end

  @doc "Apply a map of field updates to the registry entry for `agent_id`."
  @spec update(String.t(), map()) :: :ok | {:error, :not_registered}
  def update(agent_id, fields) do
    case Registry.update_value(@type_iv_registry, {:agent, agent_id}, fn meta ->
           Map.merge(meta, fields)
         end) do
      {_new, _old} -> :ok
      :error -> {:error, :not_registered}
    end
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp extract_tmux_target(%{type: :tmux, session: session}), do: session
  defp extract_tmux_target(_), do: nil

  defp extract_session_name(nil), do: nil
  defp extract_session_name(target), do: target |> String.split(":") |> hd()

  defp backend_type(nil), do: nil
  defp backend_type(%{type: type}), do: type
  defp backend_type(_), do: :unknown

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp merge_current_tool(fields, %{hook_event_type: type, tool_name: tool})
       when type in [:PreToolUse, "PreToolUse"] and not is_nil(tool),
       do: Map.put(fields, :current_tool, tool)

  defp merge_current_tool(fields, %{hook_event_type: type})
       when type in [:PostToolUse, :PostToolUseFailure, "PostToolUse", "PostToolUseFailure"],
       do: Map.put(fields, :current_tool, nil)

  defp merge_current_tool(fields, _event), do: fields
end
