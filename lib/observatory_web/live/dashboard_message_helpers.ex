defmodule ObservatoryWeb.DashboardMessageHelpers do
  @moduledoc """
  Message threading and grouping helpers for the Observatory Dashboard.
  Groups messages by conversation pairs for easier navigation.
  """

  @doc """
  Group messages by conversation thread (sender <-> recipient pairs).
  Returns a list of threads, each containing:
  - participants: sorted list of [sender, recipient]
  - messages: all messages in this thread
  - unread_count: number of unread messages
  - last_message_at: timestamp of most recent message
  - has_urgent: true if contains shutdown_request or plan_approval_request
  - message_types: set of unique message types in thread
  """
  def group_messages_by_thread(messages) do
    messages
    |> Enum.group_by(&thread_key/1)
    |> Enum.map(fn {key, thread_messages} ->
      sorted_messages = Enum.sort_by(thread_messages, & &1.timestamp, {:desc, DateTime})
      latest = List.first(sorted_messages)

      message_types = thread_messages |> Enum.map(& &1.type) |> Enum.uniq()
      has_urgent =
        Enum.any?(message_types, fn t ->
          t in ["shutdown_request", "plan_approval_request", "shutdown_response"]
        end)

      %{
        participants: key,
        messages: sorted_messages,
        unread_count: Enum.count(thread_messages, fn m -> Map.get(m, :read, true) == false end),
        last_message_at: latest.timestamp,
        has_urgent: has_urgent,
        message_types: message_types
      }
    end)
    |> Enum.sort_by(& &1.last_message_at, {:desc, DateTime})
  end

  # Generate a conversation key for a message.
  # Returns a sorted tuple of [sender, recipient] to group bidirectional conversations.
  defp thread_key(message) do
    sender = message.sender_session
    recipient = message.recipient || "all"

    # Sort to ensure [A, B] and [B, A] map to same thread
    [sender, recipient] |> Enum.sort()
  end

  @doc """
  Filter threads by participant (sender or recipient).
  """
  def filter_threads_by_participant(threads, nil), do: threads

  def filter_threads_by_participant(threads, participant) do
    Enum.filter(threads, fn thread ->
      participant in thread.participants
    end)
  end

  @doc """
  Format participant names for display.
  Returns a string like "alice <-> bob" or "alice <-> all".
  """
  def format_participants(participants) do
    case participants do
      [a, b] -> "#{short_id(a)} <-> #{short_id(b)}"
      [single] -> short_id(single)
      _ -> "unknown"
    end
  end

  @doc """
  Get message type icon and color classes.
  Returns {icon_svg, color_class}.
  """
  def message_type_icon(type) do
    case type do
      "message" ->
        {"💬", "text-zinc-400"}

      "broadcast" ->
        {"📢", "text-amber-400"}

      "shutdown_request" ->
        {"⚠️", "text-red-400"}

      "shutdown_response" ->
        {"✓", "text-emerald-400"}

      "plan_approval_request" ->
        {"📋", "text-blue-400"}

      "plan_approval_response" ->
        {"✓", "text-emerald-400"}

      _ ->
        {"•", "text-zinc-600"}
    end
  end

  @doc """
  Search messages by content or participant.
  """
  def search_messages(messages, query) when is_binary(query) and query != "" do
    query_lower = String.downcase(query)

    Enum.filter(messages, fn msg ->
      content_match = msg.content && String.contains?(String.downcase(msg.content), query_lower)

      sender_match =
        msg.sender_session && String.contains?(String.downcase(msg.sender_session), query_lower)

      recipient_match =
        msg.recipient && String.contains?(String.downcase(msg.recipient), query_lower)

      content_match || sender_match || recipient_match
    end)
  end

  def search_messages(messages, _query), do: messages

  @doc """
  Extract unique participants from messages (for filtering).
  """
  def extract_participants(messages) do
    messages
    |> Enum.flat_map(fn msg ->
      [msg.sender_session, msg.recipient || "all"]
    end)
    |> Enum.uniq()
    |> Enum.sort()
  end

  @doc """
  Get border class for message based on type.
  """
  def message_border_class(type) do
    case type do
      "broadcast" -> "border-amber-500/20 bg-amber-500/5"
      "shutdown_request" -> "border-red-500/20 bg-red-500/5"
      "shutdown_response" -> "border-emerald-500/20 bg-emerald-500/5"
      "plan_approval_request" -> "border-blue-500/20 bg-blue-500/5"
      "plan_approval_response" -> "border-emerald-500/20 bg-emerald-500/5"
      _ -> "border-zinc-700/50 bg-zinc-800/30"
    end
  end

  @doc """
  Get badge class for message type.
  """
  def message_type_badge_class(type) do
    case type do
      "broadcast" -> "bg-amber-500/15 text-amber-400"
      "shutdown_request" -> "bg-red-500/15 text-red-400"
      "shutdown_response" -> "bg-emerald-500/15 text-emerald-400"
      "plan_approval_request" -> "bg-blue-500/15 text-blue-400"
      "plan_approval_response" -> "bg-emerald-500/15 text-emerald-400"
      _ -> "bg-zinc-700 text-zinc-500"
    end
  end

  @doc """
  Generate a stable key for thread collapse state.
  """
  def participant_key(participants) when is_list(participants) do
    Enum.join(participants, "<->")
  end

  defp short_id(id) when is_binary(id) do
    if String.length(id) > 12 do
      String.slice(id, 0..11)
    else
      id
    end
  end

  defp short_id(_), do: "?"
end
