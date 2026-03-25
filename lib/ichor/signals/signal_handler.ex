defmodule Ichor.Signals.SignalHandler do
  @moduledoc """
  Downstream reaction to emitted signals.

  Pattern matches on signal name and dispatches to the appropriate action.
  Called async from SignalProcess via Task.Supervisor -- never blocks
  the accumulation pipeline.

  In production this dispatches to: Oban jobs, Ash actions, Bus notifications.
  """

  require Logger

  alias Ichor.Signals.Signal

  @spec handle(Signal.t()) :: :ok
  def handle(%Signal{name: "agent.tool.budget.exhausted"} = signal) do
    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} count=#{signal.metadata[:count]}/#{signal.metadata[:limit]}"
    )

    :ok
  end

  def handle(%Signal{name: "agent.entropy.loop.detected"} = signal) do
    score = signal.metadata[:entropy_score]
    severity = signal.metadata[:severity]

    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} score=#{score} severity=#{severity}"
    )

    case severity do
      :loop ->
        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.entropy.alert", signal.key, %{
            session_id: signal.key,
            entropy_score: score
          })
        )

        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
            agent_id: signal.key,
            state: "alert_entropy"
          })
        )

      :warning ->
        Ichor.Events.emit(
          Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
            agent_id: signal.key,
            state: "blocked"
          })
        )

      :normal ->
        if signal.metadata[:prior_severity] in [:warning, :loop] do
          Ichor.Events.emit(
            Ichor.Events.Event.new("gateway.node.state_update", signal.key, %{
              agent_id: signal.key,
              state: "active"
            })
          )
        end

      _ ->
        :ok
    end

    :ok
  end

  def handle(%Signal{name: "agent.message.protocol.violated"} = signal) do
    violations = signal.metadata[:violations] || []
    Logger.warning("[Signal] #{signal.name} team=#{signal.key} violations=#{length(violations)}")

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content: "Protocol violation in team #{signal.key}: #{length(violations)} violation(s)",
      type: :alert
    })

    :ok
  end

  def handle(%Signal{name: "agent.crash.rate"} = signal) do
    Logger.error(
      "[Signal] #{signal.name} team=#{signal.key} crashes=#{signal.metadata[:crash_count]}"
    )

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Agent crash rate exceeded in team #{signal.key}: #{signal.metadata[:crash_count]} crashes",
      type: :alert
    })

    :ok
  end

  def handle(%Signal{name: "agent.silence"} = signal) do
    Logger.warning(
      "[Signal] #{signal.name} session=#{signal.key} silent_for=#{signal.metadata[:silent_for_seconds]}s"
    )

    :ok
  end

  def handle(%Signal{name: "pipeline.stalled"} = signal) do
    Logger.warning(
      "[Signal] #{signal.name} run=#{signal.key} stalled_for=#{signal.metadata[:stalled_for_seconds]}s"
    )

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Pipeline #{signal.key} stalled: no progress for #{signal.metadata[:stalled_for_seconds]}s",
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
