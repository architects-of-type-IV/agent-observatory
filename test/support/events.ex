defmodule FleetAnalysis.TestEvents do
  @moduledoc "Builders for the event maps the analysis functions read."

  @base ~U[2026-01-01 12:00:00Z]

  @doc "A reference clock, so tests never depend on the real one."
  def now, do: @base

  @doc "A time `seconds` before `now/0`."
  def ago(seconds), do: DateTime.add(@base, -seconds, :second)

  @doc """
  Build an event.

  Defaults to a `:PreToolUse` at `now/0` for session `"s1"`; override anything.
  """
  def event(attrs \\ []) do
    Enum.into(attrs, %{
      inserted_at: @base,
      session_id: "s1",
      source_app: "app",
      hook_event_type: :PreToolUse,
      tool_name: "Read",
      payload: %{},
      model_name: nil,
      cwd: nil,
      permission_mode: nil,
      tmux_session: nil
    })
  end

  @doc "`n` consecutive `:PreToolUse` events for the same tool."
  def tool_run(tool, n, attrs \\ []) do
    for _ <- 1..n, do: event(Keyword.merge([tool_name: tool], attrs))
  end

  @doc "A team record with the given member maps."
  def team(name, members), do: %{name: name, members: members}

  @doc "A team member."
  def member(attrs \\ []) do
    Enum.into(attrs, %{agent_id: "s1", name: nil, agent_type: nil, status: :idle})
  end
end
