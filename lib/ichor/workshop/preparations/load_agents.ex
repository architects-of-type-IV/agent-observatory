defmodule Ichor.Workshop.Preparations.LoadAgents do
  @moduledoc """
  Loads agent view records from the live runtime registry.
  """

  use Ash.Resource.Preparation

  alias Ash.DataLayer.Simple
  alias Ichor.Infrastructure.AgentProcess
  alias Ichor.Workshop.Agent

  @impl true
  def prepare(query, _opts, _context) do
    agents =
      AgentProcess.list_all()
      |> Enum.map(fn {id, meta} -> to_agent(id, meta) end)
      |> Enum.sort_by(fn a -> {status_sort(a.status), a.name} end)

    Simple.set_data(query, agents)
  end

  defp to_agent(id, meta) do
    struct!(Agent, %{
      agent_id: meta[:session_id] || id,
      session_id: meta[:session_id] || id,
      name: meta[:short_name] || meta[:name] || id,
      short_name: meta[:short_name],
      role: to_string(meta[:role] || :worker),
      model: meta[:model],
      status: normalize_status(meta[:status]),
      health: :healthy,
      current_tool: meta[:current_tool],
      event_count: 0,
      tool_count: 0,
      cwd: meta[:cwd],
      source_app: nil,
      project: if(meta[:cwd], do: Path.basename(meta[:cwd]), else: nil),
      health_issues: [],
      team_name: meta[:team],
      tmux_session: get_in(meta, [:channels, :tmux]),
      host: meta[:host] || "local",
      channels: meta[:channels] || %{},
      os_pid: meta[:os_pid],
      last_event_at: meta[:last_event_at],
      subagents: [],
      recent_activity: []
    })
  end

  defp normalize_status(:active), do: :active
  defp normalize_status(:idle), do: :idle
  defp normalize_status(:ended), do: :ended
  defp normalize_status(:paused), do: :idle
  defp normalize_status(_), do: :idle

  defp status_sort(:active), do: 0
  defp status_sort(:idle), do: 1
  defp status_sort(_), do: 2
end
