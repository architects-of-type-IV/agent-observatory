defmodule IchorWeb.PresentationTest do
  use ExUnit.Case, async: true

  alias IchorWeb.Presentation

  test "short_id handles reserved identifiers" do
    assert Presentation.short_id(nil) == "?"
    assert Presentation.short_id("unknown") == "?"
    assert Presentation.short_id("broadcast") == "all"
    assert Presentation.short_id("dashboard") == "operator"
  end

  test "format_time formats datetimes and iso strings" do
    dt = ~U[2026-03-18 12:34:56Z]

    assert Presentation.format_time(dt, "%H:%M") == "12:34"
    assert Presentation.format_time("2026-03-18T12:34:56Z", "%H:%M:%S") == "12:34:56"
    assert Presentation.format_time(nil, "%H:%M") == ""
  end

  test "safe_string normalizes display values" do
    assert Presentation.safe_string(nil) == ""
    assert Presentation.safe_string(:active) == "active"
    assert Presentation.safe_string(%{ok: true}) =~ "ok"
  end

  test "status palette helpers stay consistent" do
    assert Presentation.member_status_dot_class(:active) == "bg-success"
    assert Presentation.member_status_text_class(:ended) == "text-muted"
    assert Presentation.severity_bg_class("high") == "bg-error"
    assert Presentation.task_status_text_class("blocked") == "text-brand"
  end
end
