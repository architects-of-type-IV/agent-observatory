defmodule Ichor.Signals.Team.CommViolation do
  @moduledoc """
  Fires when comm rule violations accumulate for a team.

  Key: team_name
  """

  use Ichor.Signal

  @impl true
  def name, do: :comm_violation

  @impl true
  def accepts?(%Event{topic: "team.comm.rule.broken"}), do: true
  def accepts?(_event), do: false

  @impl true
  def init(key), do: %{key: key, events: [], count: 0}

  @impl true
  def handle_event(%Event{} = event, state) do
    %{state | events: [event | state.events], count: state.count + 1}
  end

  @impl true
  def ready?(state, :event), do: state.count > 0
  def ready?(_state, _trigger), do: false

  @impl true
  def build_signal(state) do
    Signal.new("team.comm.violation", state.key, Enum.reverse(state.events), %{
      count: state.count
    })
  end

  @impl true
  def reset(state), do: %{state | events: [], count: 0}
end
