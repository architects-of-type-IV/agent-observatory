defmodule ObservatoryWeb.SessionDrilldownLive do
  @moduledoc """
  LiveView for operator HITL actions on a specific session.

  Shows the HITL state for a session and provides approve/rewrite/reject buttons.
  """

  use ObservatoryWeb, :live_view

  alias Observatory.Gateway.HITLRelay

  @impl true
  def mount(_params, %{"session_id" => session_id}, socket) do
    if connected?(socket) do
      Phoenix.PubSub.subscribe(Observatory.PubSub, "session:hitl:#{session_id}")
    end

    status = HITLRelay.session_status(session_id)

    {:ok,
     assign(socket,
       session_id: session_id,
       hitl_status: status,
       flash_msg: nil
     )}
  end

  @impl true
  def handle_event("approve", _params, socket) do
    session_id = socket.assigns.session_id

    case HITLRelay.unpause(session_id, "operator", "dashboard_operator") do
      {:ok, :not_paused} ->
        {:noreply, assign(socket, flash_msg: "Session was not paused.")}

      {:ok, count} when is_integer(count) ->
        {:noreply,
         assign(socket,
           hitl_status: :normal,
           flash_msg: "Approved. Flushed #{count} messages."
         )}
    end
  end

  def handle_event("reject", %{"reason" => reason}, socket) do
    session_id = socket.assigns.session_id
    HITLRelay.unpause(session_id, "operator", "dashboard_operator")
    {:noreply, assign(socket, hitl_status: :normal, flash_msg: "Rejected. Reason: #{reason}")}
  end

  def handle_event("rewrite", %{"trace_id" => trace_id, "new_payload" => new_payload}, socket) do
    session_id = socket.assigns.session_id

    case Jason.decode(new_payload) do
      {:ok, decoded} ->
        case HITLRelay.rewrite(session_id, trace_id, decoded) do
          :ok ->
            {:noreply, assign(socket, flash_msg: "Message rewritten.")}

          {:error, :not_found} ->
            {:noreply, assign(socket, flash_msg: "Message not found in buffer.")}
        end

      {:error, _} ->
        {:noreply, assign(socket, flash_msg: "Invalid JSON payload.")}
    end
  end

  @impl true
  def handle_info({:hitl, _event}, socket) do
    status = HITLRelay.session_status(socket.assigns.session_id)
    {:noreply, assign(socket, hitl_status: status)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="p-4">
      <h2 class="text-lg font-bold mb-4">Session: {@session_id}</h2>

      <div class="mb-4">
        <span class="font-medium">HITL Status: </span>
        <span class={if @hitl_status == :paused, do: "text-yellow-500 font-bold", else: "text-green-500"}>
          {@hitl_status}
        </span>
      </div>

      <%= if @flash_msg do %>
        <div class="mb-4 p-2 bg-blue-100 text-blue-800 rounded">{@flash_msg}</div>
      <% end %>

      <%= if @hitl_status == :paused do %>
        <div class="space-y-2">
          <button phx-click="approve" class="px-4 py-2 bg-green-600 text-white rounded hover:bg-green-700">
            Approve (Flush Buffer)
          </button>

          <form phx-submit="reject" class="inline">
            <input type="text" name="reason" placeholder="Rejection reason" class="border rounded px-2 py-1" />
            <button type="submit" class="px-4 py-2 bg-red-600 text-white rounded hover:bg-red-700">
              Reject
            </button>
          </form>

          <form phx-submit="rewrite" class="mt-2">
            <input type="text" name="trace_id" placeholder="Trace ID" class="border rounded px-2 py-1" />
            <textarea name="new_payload" placeholder='{"key": "value"}' class="border rounded px-2 py-1 w-full mt-1"></textarea>
            <button type="submit" class="px-4 py-2 bg-blue-600 text-white rounded hover:bg-blue-700 mt-1">
              Rewrite Message
            </button>
          </form>
        </div>
      <% end %>
    </div>
    """
  end
end
