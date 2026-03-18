defmodule Ichor.Tools.MessagingTest do
  use ExUnit.Case, async: true

  test "send_as_operator delegates through operator and preserves result shape" do
    assert {:ok, %{status: "sent", to: "operator", delivered: delivered}} =
             Ichor.Tools.Messaging.send_as_operator("operator", "status")

    assert is_integer(delivered)
  end
end
