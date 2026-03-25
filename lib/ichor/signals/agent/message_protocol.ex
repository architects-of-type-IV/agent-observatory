defmodule Ichor.Signals.Agent.MessageProtocol do
  @moduledoc """
  Signal projector that watches `agent.message.sent` events per team.

  Checks intercepted messages against the comm_rules defined on the
  Workshop team blueprint. Fires `"agent.message.protocol.violated"` when
  a message matches a deny rule.

  Key: team_name (string). Rules are loaded at `init_state/1` and cached
  for the lifetime of the signal process.

  ## CommRule semantics

  `%Ichor.Workshop.CommRule{from: integer, to: integer, policy: "deny", via: integer | nil}`

  - `from`/`to` are agent slot indices (integers) within the team blueprint.
  - `policy: "deny"` blocks direct communication between those slots.
  - A rule with `policy` other than `"deny"` is ignored by this projector.
  """

  use Ichor.Signal

  require Logger

  alias Ichor.Workshop.Team

  @impl true
  @spec topics() :: [String.t()]
  def topics, do: ["agent.message.sent"]

  @impl true
  @spec init_state(term()) :: map()
  def init_state(key) do
    send(self(), {:load_rules, key})
    %{key: key, events: [], violations: [], rules: :pending, metadata: %{}}
  end

  @impl true
  @spec handle_event(map(), Ichor.Events.Event.t()) :: map()
  def handle_event(%{rules: :pending} = state, event) do
    %{state | events: [event | state.events]}
  end

  def handle_event(state, event) do
    case check_violation(event, state.rules) do
      nil ->
        %{state | events: [event | state.events]}

      violation ->
        %{state | events: [event | state.events], violations: [violation | state.violations]}
    end
  end

  @impl true
  @spec ready?(map(), :event | :timer) :: boolean()
  def ready?(state, _trigger), do: state.violations != []

  @impl true
  @spec signal_name() :: String.t()
  def signal_name, do: "agent.message.protocol.violated"

  @impl true
  @spec build_signal(map()) :: Ichor.Signals.Signal.t()
  def build_signal(state) do
    Ichor.Signals.Signal.new(
      signal_name(),
      state.key,
      Enum.reverse(state.events),
      %{
        violations: Enum.reverse(state.violations),
        rule_count: if(is_list(state.rules), do: length(state.rules), else: 0)
      }
    )
  end

  @impl true
  def handle(%Ichor.Signals.Signal{} = signal) do
    violations = signal.metadata[:violations] || []
    Logger.warning("[Signal] #{signal.name} team=#{signal.key} violations=#{length(violations)}")

    Ichor.Signals.Bus.send(%{
      from: "system",
      to: "operator",
      content:
        "Protocol violation in team #{signal.key}: #{length(violations)} violation(s) detected",
      type: :alert
    })

    :ok
  end

  @impl true
  @spec reset(map()) :: map()
  def reset(state), do: %{state | events: [], violations: [], metadata: %{}}

  @spec handle_info(map(), term()) :: map()
  def handle_info(state, {:load_rules, key}) do
    %{state | rules: load_comm_rules(key)}
  end

  def handle_info(state, _msg), do: state

  @spec load_comm_rules(String.t()) :: [map()]
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

  @spec check_violation(Ichor.Events.Event.t(), [Ichor.Workshop.CommRule.t()]) :: map() | nil
  defp check_violation(event, rules) do
    from = get_field(event.data, :from) || get_field(event.data, "from")
    to = get_field(event.data, :to) || get_field(event.data, "to")

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

  defp slot_matches?(slot, value) when is_integer(slot) and is_binary(value) do
    value == Integer.to_string(slot)
  end

  defp slot_matches?(slot, value) when is_integer(slot) and is_integer(value) do
    slot == value
  end

  defp slot_matches?(slot, value) do
    slot == value
  end

  defp get_field(data, key) when is_map(data), do: Map.get(data, key)
  defp get_field(_, _), do: nil
end
