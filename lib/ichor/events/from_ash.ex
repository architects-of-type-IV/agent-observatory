defmodule Ichor.Events.FromAsh do
  @moduledoc """
  Ash notifier stub. Previously bridged Ash mutations into the GenStage event
  pipeline; that pipeline has been removed. Kept as an attachment point for
  resources that list it as a simple_notifier so the Ash DSL compiles cleanly.
  """

  use Ash.Notifier

  @impl true
  def notify(%Ash.Notifier.Notification{}), do: :ok
end
