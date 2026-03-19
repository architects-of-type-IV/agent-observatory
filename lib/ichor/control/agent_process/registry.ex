defmodule Ichor.Control.AgentProcess.Registry do
  @moduledoc """
  Registry projection and event-derived metadata shaping for agent processes.
  """

  @type_iv_registry Ichor.Registry

  @doc "Build the initial registry metadata map for a newly started agent."
  @spec build_initial_meta(String.t(), Ichor.Control.AgentProcess.t(), map()) :: map()
  def build_initial_meta(id, state, meta) do
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

  @doc "Derive registry field updates from an agent event payload."
  @spec fields_from_event(map()) :: map()
  def fields_from_event(event) do
    %{last_event_at: DateTime.utc_now(), status: :active}
    |> maybe_merge(:model, Map.get(event, :model_name))
    |> maybe_merge(:cwd, Map.get(event, :cwd))
    |> maybe_merge(:os_pid, Map.get(event, :os_pid))
    |> merge_current_tool(event)
  end

  @doc "Merge `fields` into the registry metadata for the given agent ID."
  @spec update(String.t(), map()) :: {term(), term()} | :error
  def update(id, fields) do
    Registry.update_value(@type_iv_registry, {:agent, id}, fn meta -> Map.merge(meta, fields) end)
  end

  defp extract_tmux_target(%{type: :tmux, session: session}), do: session
  defp extract_tmux_target(_), do: nil

  defp extract_session_name(nil), do: nil
  defp extract_session_name(target), do: target |> String.split(":") |> hd()

  defp backend_type(nil), do: nil
  defp backend_type(%{type: type}), do: type
  defp backend_type(_), do: :unknown

  defp maybe_merge(map, _key, nil), do: map
  defp maybe_merge(map, key, value), do: Map.put(map, key, value)

  defp merge_current_tool(fields, %{hook_event_type: type, tool_name: tool})
       when type in [:PreToolUse, "PreToolUse"] and not is_nil(tool),
       do: Map.put(fields, :current_tool, tool)

  defp merge_current_tool(fields, %{hook_event_type: type})
       when type in [:PostToolUse, :PostToolUseFailure, "PostToolUse", "PostToolUseFailure"],
       do: Map.put(fields, :current_tool, nil)

  defp merge_current_tool(fields, _event), do: fields
end
