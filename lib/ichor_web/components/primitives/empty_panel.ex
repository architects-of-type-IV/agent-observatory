defmodule IchorWeb.Components.Primitives.EmptyPanel do
  @moduledoc """
  Reusable centered empty state for panels. Renders muted title and optional description text.
  """

  use Phoenix.Component

  @doc """
  Renders a centered empty state with optional title and description.

  ## Examples

      <.empty_panel title="No agents detected" description="Start a Claude session to see it here." />

      <.empty_panel title="No messages yet" class="py-12" />
  """
  attr :title, :string, default: nil
  attr :description, :string, default: nil
  attr :class, :string, default: "py-8"

  def empty_panel(assigns) do
    ~H"""
    <div class={"text-center " <> @class}>
      <p :if={@title} class="text-[10px] text-muted uppercase tracking-wider mb-1">{@title}</p>
      <p :if={@description} class="text-[10px] text-muted">{@description}</p>
    </div>
    """
  end
end
