defmodule Ichor.Signal do
  @moduledoc """
  Macro for declarative Signal module definitions.

  Analogous to `use Ash.Resource` for signals. Injects the `Ichor.Signals.Behaviour`
  contract and provides sensible defaults for all six callbacks. Override only what
  differs from the default behaviour.

  ## Usage

      defmodule Ichor.Signals.Agent.ToolBudget do
        use Ichor.Signal

        @impl true
        def topics, do: ["agent.tool.completed"]

        @impl true
        def ready?(state, _trigger), do: state.count >= state.limit
      end

  ## Signal name derivation

  The default `signal_name/0` converts the module path after `Signals` to a
  dot-delimited string:

      Ichor.Signals.Agent.ToolBudget  ->  "agent.tool.budget"
  """

  defmacro __using__(_opts) do
    quote do
      @behaviour Ichor.Signals.Behaviour

      alias Ichor.Signals.Signal

      @impl true
      @spec signal_name() :: String.t()
      def signal_name do
        __MODULE__
        |> Module.split()
        |> Enum.drop_while(&(&1 != "Signals"))
        |> Enum.drop(1)
        |> Enum.map_join(".", &Macro.underscore/1)
      end

      @impl true
      @spec init_state(term()) :: map()
      def init_state(key), do: %{key: key, events: [], metadata: %{}}

      @impl true
      @spec handle_event(map(), Ichor.Events.Event.t()) :: map()
      def handle_event(state, event) do
        %{state | events: [event | state.events]}
      end

      @impl true
      @spec ready?(map(), :event | :timer) :: boolean()
      def ready?(_state, _trigger), do: false

      @impl true
      @spec build_signal(map()) :: Ichor.Signals.Signal.t()
      def build_signal(state) do
        Signal.new(
          signal_name(),
          state.key,
          Enum.reverse(state.events),
          state.metadata
        )
      end

      @impl true
      @spec reset(map()) :: map()
      def reset(state), do: %{state | events: [], metadata: %{}}

      @spec handle_info(map(), term()) :: map()
      def handle_info(state, _msg), do: state

      defoverridable init_state: 1,
                     handle_event: 2,
                     ready?: 2,
                     build_signal: 1,
                     reset: 1,
                     signal_name: 0,
                     handle_info: 2
    end
  end
end
