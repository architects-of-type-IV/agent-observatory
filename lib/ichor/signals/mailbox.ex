defmodule Ichor.Signals.Mailbox do
  @moduledoc """
  Action-only signal mailbox surface for operator-facing message intake.
  """

  use Ash.Resource, domain: Ichor.SignalBus

  alias Ichor.Control.AgentProcess

  actions do
    action :check_operator_inbox, {:array, :map} do
      description("Read unread messages addressed to the operator mailbox.")

      run(fn _input, _context ->
        try do
          messages = AgentProcess.get_unread("operator")

          {:ok,
           Enum.map(messages, fn message ->
             %{
               "from" => message[:from] || message["from"],
               "content" => message[:content] || message["content"],
               "timestamp" => message[:timestamp] || message["timestamp"]
             }
           end)}
        rescue
          e in [RuntimeError, ArgumentError, KeyError] ->
            require Logger
            Logger.warning("check_operator_inbox failed: #{Exception.message(e)}")
            {:ok, []}
        end
      end)
    end
  end

  code_interface do
    define(:check_operator_inbox)
  end
end
