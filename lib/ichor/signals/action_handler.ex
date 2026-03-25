defmodule Ichor.Signals.ActionHandler do
  @moduledoc """
  Dispatches signal activations to real system actions.

  Each signal name maps to a concrete response: pausing an agent via HITL,
  notifying the operator via Bus, or logging for unknown signals.
  """

  require Logger

  alias Ichor.Signals
  alias Ichor.Signals.Signal

  @tool_budget Ichor.Signals.Agent.ToolBudget.signal_name()
  @entropy Ichor.Signals.Agent.Entropy.signal_name()
  @protocol Ichor.Signals.Agent.MessageProtocol.signal_name()

  @doc "Dispatch a signal to the appropriate system action."
  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{name: @tool_budget} = signal) do
    session_id = signal.key
    count = signal.metadata[:count]
    limit = signal.metadata[:limit]

    Logger.warning("[Signal] #{signal.name} session=#{session_id} count=#{count}/#{limit}")

    case Ichor.Infrastructure.HITLRelay.pause(
           session_id,
           "system",
           "system",
           "Tool budget exhausted (#{count}/#{limit})"
         ) do
      :ok ->
        :ok

      {:ok, :already_paused} ->
        Logger.debug("[Signal] Session #{session_id} already paused, skipping")
        :ok

      {:error, reason} ->
        Logger.warning("[Signal] Failed to pause #{session_id}: #{inspect(reason)}")
        :ok
    end
  end

  def handle(%Signal{name: @entropy} = signal) do
    session_id = signal.key
    score = signal.metadata[:entropy_score]
    severity = signal.metadata[:severity]
    prior = signal.metadata[:prior_severity]

    Logger.warning(
      "[Signal] #{signal.name} session=#{session_id} score=#{score} severity=#{severity}"
    )

    case severity do
      :loop ->
        Signals.emit(:entropy_alert, %{session_id: session_id, entropy_score: score})
        Signals.emit(:node_state_update, %{agent_id: session_id, state: "alert_entropy"})

      :warning ->
        Signals.emit(:node_state_update, %{agent_id: session_id, state: "blocked"})

      :normal when prior in [:warning, :loop] ->
        Signals.emit(:node_state_update, %{agent_id: session_id, state: "active"})

      :normal ->
        :ok
    end

    :ok
  end

  def handle(%Signal{name: @protocol} = signal) do
    team_name = signal.key
    violations = signal.metadata[:violations] || []

    Logger.warning("[Signal] #{signal.name} team=#{team_name} violations=#{length(violations)}")

    Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Protocol violation in team #{team_name}: #{length(violations)} violation(s) detected",
      type: :alert
    })

    :ok
  end

  def handle(%Signal{} = signal) do
    Logger.info(
      "[Signal] #{signal.name} key=#{inspect(signal.key)} events=#{length(signal.events)}"
    )

    :ok
  end
end
