defmodule Ichor.PubSub do
  @moduledoc "Stub name for standalone compilation. Host VM provides Phoenix.PubSub."
end

unless Code.ensure_loaded?(Phoenix.PubSub) do
  defmodule Phoenix.PubSub do
    @moduledoc "Stub for standalone compilation."
    def unsubscribe(_pubsub, _topic), do: :ok
  end
end
