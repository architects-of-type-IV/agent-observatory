defmodule IchorWeb.DashboardNotesHandlers do
  @moduledoc """
  Handles note-related events for the dashboard LiveView.
  """

  def dispatch("add_note", p, s) do
    {:noreply, socket} = handle_add_note(p, s)
    socket
  end

  def dispatch("delete_note", p, s) do
    {:noreply, socket} = handle_delete_note(p, s)
    socket
  end

  def handle_add_note(%{"event_id" => event_id, "text" => text}, socket) do
    {:ok, _note} = Ichor.Notes.add_note(event_id, text)

    socket =
      Phoenix.LiveView.push_event(socket, "toast", %{
        message: "Note added",
        type: "success"
      })

    {:noreply, socket}
  end

  def handle_delete_note(%{"event_id" => event_id}, socket) do
    Ichor.Notes.delete_note(event_id)

    socket =
      Phoenix.LiveView.push_event(socket, "toast", %{
        message: "Note deleted",
        type: "success"
      })

    {:noreply, socket}
  end
end
