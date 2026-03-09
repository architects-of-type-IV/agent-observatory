defmodule ObservatoryWeb.Components.Observatory.SessionIdentity do
  @moduledoc """
  Reusable session identity element: colored dot + short session ID.
  Used across sidebar, feed, errors, timeline, and message threads.
  """
  use Phoenix.Component

  import ObservatoryWeb.DashboardFormatHelpers, only: [session_color: 1, short_session: 1]

  attr :session_id, :string, required: true
  attr :ended, :boolean, default: false
  attr :class, :string, default: ""

  def session_identity(assigns) do
    {bg, _border, _text} = session_color(assigns.session_id)
    assigns = assign(assigns, :bg, bg)

    ~H"""
    <span class={"inline-flex items-center gap-1 #{@class}"}>
      <span class={"w-1.5 h-1.5 rounded-full shrink-0 #{@bg} #{if @ended, do: "opacity-30", else: ""}"} />
      <span class="si-meta font-mono">{short_session(@session_id)}</span>
    </span>
    """
  end
end
