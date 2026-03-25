defmodule Ichor.Signals.Agent.ToolBudget do
  @moduledoc """
  Signal projector that watches `agent.tool.completed` events per session.

  Fires `"agent.tool.budget.exhausted"` when the tool count for a session
  exceeds the configured limit. The default limit is 500 tool calls per
  session lifecycle.

  Key: session_id (string)
  """

  use Ichor.Signal

  @default_limit 500

  @impl true
  @spec topics() :: [String.t()]
  def topics, do: ["agent.tool.completed"]

  @impl true
  @spec init_state(term()) :: map()
  def init_state(key) do
    %{key: key, events: [], count: 0, limit: @default_limit, metadata: %{}}
  end

  @impl true
  @spec handle_event(map(), Ichor.Events.Event.t()) :: map()
  def handle_event(state, _event) do
    %{state | count: state.count + 1}
  end

  @impl true
  @spec ready?(map(), :event | :timer) :: boolean()
  def ready?(state, _trigger), do: state.count >= state.limit

  @impl true
  @spec signal_name() :: String.t()
  def signal_name, do: "agent.tool.budget.exhausted"

  @impl true
  @spec build_signal(map()) :: Ichor.Signals.Signal.t()
  def build_signal(state) do
    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      [],
      %{count: state.count, limit: state.limit}
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    require Logger

    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} count=#{signal.metadata[:count]}/#{signal.metadata[:limit]}"
    )

    :ok
  end

  @impl true
  @spec reset(map()) :: map()
  def reset(state), do: %{state | count: 0, metadata: %{}}
end
