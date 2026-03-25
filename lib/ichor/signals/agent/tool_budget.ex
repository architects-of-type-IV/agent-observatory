defmodule Ichor.Signals.Agent.ToolBudget do
  @moduledoc """
  Fires when tool calls per session exceed a budget limit.

  Key: session_id
  Fires: "agent.tool.budget.exhausted"
  """

  use Ichor.Signal

  @accepted_topics ["agent.tool.completed"]
  @default_limit 500

  @impl true
  def name, do: :tool_budget

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key), do: %{key: key, events: [], count: 0, limit: @default_limit}

  @impl true
  def handle_event(_event, state), do: %{state | count: state.count + 1}

  @impl true
  def ready?(state, _trigger), do: state.count >= state.limit

  @impl true
  def build_signal(state) do
    Signal.new("agent.tool.budget.exhausted", state.key, [], %{
      count: state.count,
      limit: state.limit
    })
  end

  @impl true
  def reset(state), do: %{state | count: 0, events: []}
end
