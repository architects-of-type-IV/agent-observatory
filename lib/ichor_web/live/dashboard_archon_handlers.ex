defmodule IchorWeb.DashboardArchonHandlers do
  @moduledoc """
  LiveView event handlers for the Archon overlay.
  Chat messages are dispatched async via Task to avoid blocking the LiveView process.
  """

  import Phoenix.Component, only: [assign: 3]

  alias Ichor.Archon.Chat
  alias Ichor.Archon.SignalManager

  require Logger

  @doc "Toggle the Archon overlay visibility."
  def handle_archon_toggle(socket) do
    if socket.assigns.show_archon do
      assign(socket, :show_archon, false)
    else
      socket
      |> assign(:show_archon, true)
      |> assign(:archon_tab, :command)
      |> refresh_manager_state()
    end
  end

  @doc "Close the Archon overlay."
  def handle_archon_close(socket) do
    assign(socket, :show_archon, false)
  end

  @doc "Refresh Archon's manager-facing snapshot assigns."
  def refresh_manager_state(socket) do
    socket
    |> assign(:archon_snapshot, SignalManager.snapshot())
    |> assign(:archon_attention, SignalManager.attention())
  rescue
    _ -> socket
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
    user_input = last_user_input(socket.assigns.archon_messages)
    persist_turn(user_input, response)

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

  alias Ichor.Infrastructure.MemoriesClient

  defp build_response_msg(%{type: type, data: data}),
    do: %{role: :assistant, type: type, data: data, content: nil}

  defp build_response_msg(text) when is_binary(text),
    do: %{role: :assistant, type: :text, data: nil, content: text}

  defp last_user_input(messages) do
    messages
    |> Enum.reverse()
    |> Enum.find_value(fn
      %{role: :user, content: c} when is_binary(c) -> c
      _ -> nil
    end)
  end

  defp persist_turn(nil, _response), do: :ok

  defp persist_turn(user_input, response) do
    content = format_episode(user_input, response)

    Task.start(fn ->
      case MemoriesClient.ingest(content, type: "message") do
        {:ok, _} -> :ok
        {:error, reason} -> Logger.warning("[Archon] Memory ingest failed: #{inspect(reason)}")
      end
    end)
  end

  defp format_episode(user_input, %{type: type, data: data}) do
    "Architect: #{user_input}\nArchon: [#{type}] #{inspect(data, limit: 20, pretty: false)}"
  end

  defp format_episode(user_input, text) when is_binary(text) do
    "Architect: #{user_input}\nArchon: #{text}"
  end

  defp dispatch_shortcode(content, socket) do
    start_chat_task(content, socket.assigns.archon_history)

    socket
    |> assign(:archon_messages, [])
    |> assign(:archon_loading, true)
    |> assign(:show_archon, true)
    |> refresh_manager_state()
  end

  defp dispatch_message(content, socket) do
    user_msg = %{role: :user, content: content}
    start_chat_task(content, socket.assigns.archon_history)

    socket
    |> assign(:archon_messages, socket.assigns.archon_messages ++ [user_msg])
    |> assign(:archon_loading, true)
    |> assign(:show_archon, true)
    |> refresh_manager_state()
  end

  defp start_chat_task(content, history) do
    lv = self()

    Task.start(fn ->
      result = Chat.chat(content, history)
      send(lv, {:archon_response, result})
    end)
  end
end
