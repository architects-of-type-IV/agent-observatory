defmodule Ichor.Signals.Agent.MessageProtocol do
  @moduledoc """
  Fires when an intercepted message violates team comm rules.

  Key: team_name
  Fires: "agent.message.protocol.violated"
  """

  use Ichor.Signal

  require Logger

  alias Ichor.Workshop.Team

  @accepted_topics ["agent.message.sent"]

  @impl true
  def name, do: :message_protocol

  @impl true
  def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

  @impl true
  def init(key) do
    send(self(), {:load_rules, key})
    %{key: key, events: [], violations: [], rules: :pending}
  end

  @impl true
  def handle_event(%Event{} = event, %{rules: :pending} = state) do
    %{state | events: [event | state.events]}
  end

  def handle_event(%Event{} = event, state) do
    case check_violation(event, state.rules) do
      nil ->
        %{state | events: [event | state.events]}

      violation ->
        %{state | events: [event | state.events], violations: [violation | state.violations]}
    end
  end

  @impl true
  def ready?(state, _trigger), do: state.violations != []

  @impl true
  def build_signal(state) do
    Signal.new("agent.message.protocol.violated", state.key, Enum.reverse(state.events), %{
      violations: Enum.reverse(state.violations),
      rule_count: if(is_list(state.rules), do: length(state.rules), else: 0)
    })
  end

  @impl true
  def reset(state), do: %{state | events: [], violations: []}

  @doc false
  def handle_info(state, {:load_rules, key}), do: %{state | rules: load_comm_rules(key)}
  def handle_info(state, _msg), do: state

  defp load_comm_rules(team_name) do
    case Team.by_name(team_name) do
      {:ok, team} -> Enum.filter(team.comm_rules || [], &deny_rule?/1)
      _ -> []
    end
  rescue
    error ->
      Logger.warning(
        "[MessageProtocol] Failed to load comm rules for #{team_name}: #{inspect(error)}"
      )

      []
  end

  defp deny_rule?(%Ichor.Workshop.CommRule{policy: "deny"}), do: true
  defp deny_rule?(_), do: false

  defp check_violation(event, rules) do
    from = event.data[:from] || event.data["from"]
    to = event.data[:to] || event.data["to"]

    Enum.find_value(rules, fn rule ->
      if matches_rule?(rule, from, to) do
        %{rule_from: rule.from, rule_to: rule.to, from: from, to: to, event_id: event.id}
      end
    end)
  end

  defp matches_rule?(%Ichor.Workshop.CommRule{policy: "deny"} = rule, from, to) do
    slot_matches?(rule.from, from) and slot_matches?(rule.to, to)
  end

  defp matches_rule?(_rule, _from, _to), do: false

  defp slot_matches?(slot, value) when is_integer(slot) and is_binary(value),
    do: value == Integer.to_string(slot)

  defp slot_matches?(slot, value) when is_integer(slot) and is_integer(value), do: slot == value
  defp slot_matches?(slot, value), do: slot == value
end
