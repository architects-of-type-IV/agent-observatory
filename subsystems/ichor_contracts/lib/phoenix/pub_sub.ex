unless Code.ensure_loaded?(Phoenix.PubSub) do
  defmodule Phoenix.PubSub do
    @moduledoc "Stub for standalone compilation. Host VM provides real Phoenix.PubSub."

    def unsubscribe(_pubsub, _topic), do: :ok
  end
end
