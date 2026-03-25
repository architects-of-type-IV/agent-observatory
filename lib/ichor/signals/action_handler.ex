defmodule Ichor.Signals.ActionHandler do
  @moduledoc """
  Dispatches signal activations to real system actions.

  Each signal name maps to a concrete response: pausing an agent via HITL,
  notifying the operator via Bus, or logging for unknown signals.
  """

  require Logger

  alias Ichor.Signals.Signal

  @doc "Dispatch a signal to the appropriate system action."
  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{name: "agent.tool.budget.exhausted"} = signal) do
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

  def handle(%Signal{name: "agent.message.protocol.violated"} = signal) do
    team_name = signal.key
    violations = signal.metadata[:violations] || []

    Logger.warning("[Signal] #{signal.name} team=#{team_name} violations=#{length(violations)}")

    Ichor.Signals.Bus.send(%{
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
