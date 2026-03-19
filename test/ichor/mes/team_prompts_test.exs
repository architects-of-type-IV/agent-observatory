defmodule Ichor.Mes.TeamPromptsTest do
  use ExUnit.Case, async: true

  alias Ichor.Mes.TeamPrompts

  test "roster lists exact agent ids and operator" do
    roster = TeamPrompts.roster("mes-run-123")

    assert roster =~ "coordinator: mes-run-123-coordinator"
    assert roster =~ "researcher-2: mes-run-123-researcher-2"
    assert roster =~ "operator: operator"
  end

  test "coordinator prompt includes delivery contract and session id" do
    prompt = TeamPrompts.coordinator("run-123", TeamPrompts.roster("mes-run-123"))

    assert prompt =~ "Your session_id is: mes-run-123-coordinator"
    assert prompt =~ "TITLE: short descriptive name"
    assert prompt =~ "send_message from \"mes-run-123-coordinator\" to \"operator\""
  end

  test "corrective prompt includes failure reason and target session" do
    prompt = TeamPrompts.corrective("run-123", "mes-run-123", "missing required fields")

    assert prompt =~ "run run-123"
    assert prompt =~ "mes-run-123"
    assert prompt =~ "missing required fields"
  end
end
