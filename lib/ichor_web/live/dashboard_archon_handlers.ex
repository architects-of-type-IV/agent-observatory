defmodule IchorWeb.DashboardArchonHandlers do
  @moduledoc """
  LiveView event handlers for the Archon overlay.
  Chat messages are dispatched async via Task to avoid blocking the LiveView process.
  """

  import Phoenix.Component, only: [assign: 3]

  require Logger

  @doc "Toggle the Archon overlay visibility."
  def handle_archon_toggle(socket) do
    assign(socket, :show_archon, !socket.assigns.show_archon)
  end

  @doc "Close the Archon overlay."
  def handle_archon_close(socket) do
    assign(socket, :show_archon, false)
  end

  @doc "Execute a shortcode command, clearing previous output."
  def handle_archon_shortcode(%{"cmd" => cmd}, socket) do
    dispatch_shortcode("/" <> cmd, socket)
  end

  @doc "Send a chat message to Archon."
  def handle_archon_send(%{"content" => ""}, socket), do: socket

  def handle_archon_send(%{"content" => content}, socket) do
    dispatch_message(content, socket)
  end

  @doc "Handle async chat response from Task."
  def handle_archon_response({:ok, response, history}, socket) do
    msg = build_response_msg(response)

    socket
    |> assign(:archon_messages, socket.assigns.archon_messages ++ [msg])
    |> assign(:archon_history, history)
    |> assign(:archon_loading, false)
  end

  def handle_archon_response({:error, reason}, socket) do
    Logger.warning("Archon chat error: #{inspect(reason)}")
    msg = %{role: :assistant, content: "Error: #{inspect(reason)}"}

    socket
    |> assign(:archon_messages, socket.assigns.archon_messages ++ [msg])
    |> assign(:archon_loading, false)
  end

  # -- Private ----------------------------------------------------------------

  defp build_response_msg(%{type: type, data: data}), do: %{role: :assistant, type: type, data: data, content: nil}
  defp build_response_msg(text) when is_binary(text), do: %{role: :assistant, type: :text, data: nil, content: text}

  defp dispatch_shortcode(content, socket) do
    history = socket.assigns.archon_history
    lv = self()

    Task.start(fn ->
      result = Ichor.Archon.Chat.chat(content, history)
      send(lv, {:archon_response, result})
    end)

    socket
    |> assign(:archon_messages, [])
    |> assign(:archon_loading, true)
    |> assign(:show_archon, true)
  end

  defp dispatch_message(content, socket) do
    user_msg = %{role: :user, content: content}
    messages = socket.assigns.archon_messages ++ [user_msg]
    history = socket.assigns.archon_history
    lv = self()

    Task.start(fn ->
      result = Ichor.Archon.Chat.chat(content, history)
      send(lv, {:archon_response, result})
    end)

    socket
    |> assign(:archon_messages, messages)
    |> assign(:archon_loading, true)
    |> assign(:show_archon, true)
  end
end
