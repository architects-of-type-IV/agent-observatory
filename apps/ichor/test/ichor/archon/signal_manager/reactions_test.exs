defmodule Ichor.Archon.SignalManager.ReactionsTest do
  use ExUnit.Case, async: true

  alias Ichor.Archon.SignalManager.Reactions
  alias Ichor.Signals.Message

  test "adds attention items for high-signal failures" do
    state = Reactions.new_state()

    message = %Message{
      name: :dag_tmux_gone,
      kind: :domain,
      domain: :dag,
      data: %{run_id: "run-1", session: "dag-run-1"},
      timestamp: 10
    }

    next = Reactions.ingest(message, state)

    assert next.signal_count == 1
    assert next.counts_by_category == %{dag: 1}
    assert [%{signal: :dag_tmux_gone, severity: :critical, key: "dag:run:run-1"}] = next.attention
  end

  test "resolves matching attention on success signals" do
    failed = %Message{
      name: :mes_quality_gate_failed,
      kind: :domain,
      domain: :mes,
      data: %{run_id: "run-2", gate: "quality", reason: "tests failed"},
      timestamp: 10
    }

    passed = %Message{
      name: :mes_quality_gate_passed,
      kind: :domain,
      domain: :mes,
      data: %{run_id: "run-2", gate: "quality", session_id: "mes-run-2"},
      timestamp: 20
    }

    state =
      Reactions.new_state()
      |> then(&Reactions.ingest(failed, &1))
      |> then(&Reactions.ingest(passed, &1))

    assert state.attention == []
    assert state.latest_by_category.mes.name == :mes_quality_gate_passed
  end
end
