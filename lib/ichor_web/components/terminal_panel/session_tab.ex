defmodule IchorWeb.Components.TerminalPanel.SessionTab do
  @moduledoc """
  Individual session tab for the terminal panel header.
  Shows session name, active indicator, and close button.
  """

  use Phoenix.Component

  attr :session, :string, required: true
  attr :active, :boolean, required: true

  def session_tab(assigns) do
    ~H"""
    <button
      phx-click="switch_tmux_tab"
      phx-value-session={@session}
      class={["term-tab", if(@active, do: "active")]}
    >
      <span class={[
        "w-1.5 h-1.5 rounded-full shrink-0",
        if(@active, do: "bg-success", else: "bg-highlight")
      ]} />
      <span>{@session}</span>
      <span
        phx-click="disconnect_tmux_tab"
        phx-value-session={@session}
        class="term-tab-close"
      >
        x
      </span>
    </button>
    """
  end
end
