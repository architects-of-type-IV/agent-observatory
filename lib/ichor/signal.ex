defmodule Ichor.Signal do
  @moduledoc """
  Macro for declarative Signal module definitions.

  Injects the `Ichor.Signals.Behaviour` contract and provides sensible defaults.
  Override only what differs.

  ## Usage

      defmodule Ichor.Signals.Agent.ToolBudget do
        use Ichor.Signal

        @accepted_topics ["agent.tool.completed"]

        @impl true
        def name, do: :tool_budget

        @impl true
        def accepts?(%Event{topic: topic}), do: topic in @accepted_topics

        @impl true
        def ready?(state, _trigger), do: state.count >= 500
      end
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Ichor.Signals.Behaviour

      alias Ichor.Events.Event
      alias Ichor.Signals.Signal

      @impl true
      def name, do: :unnamed

      @impl true
      def accepts?(%Event{}), do: false

      @impl true
      def init(key), do: %{key: key, events: []}

      @impl true
      def handle_event(%Event{} = event, state) do
        %{state | events: [event | state.events]}
      end

      @impl true
      def ready?(_state, _trigger), do: false

      @impl true
      def build_signal(%{events: []}), do: nil

      def build_signal(state) do
        Signal.new(
          to_string(name()),
          state.key,
          Enum.reverse(state.events),
          %{}
        )
      end

      @impl true
      def reset(state), do: %{state | events: []}

      defoverridable name: 0,
                     accepts?: 1,
                     init: 1,
                     handle_event: 2,
                     ready?: 2,
                     build_signal: 1,
                     reset: 1
    end
  end
end
