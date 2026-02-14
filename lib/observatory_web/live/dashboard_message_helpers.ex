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
  - unread_count: number of unread messages (placeholder for future)
  - last_message_at: timestamp of most recent message
  """
  def group_messages_by_thread(messages) do
    messages
    |> Enum.group_by(&thread_key/1)
    |> Enum.map(fn {key, thread_messages} ->
      sorted_messages = Enum.sort_by(thread_messages, & &1.timestamp, {:desc, DateTime})
      latest = List.first(sorted_messages)

      %{
        participants: key,
        messages: sorted_messages,
        unread_count: 0,
        last_message_at: latest.timestamp
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

  defp short_id(id) when is_binary(id) do
    if String.length(id) > 12 do
      String.slice(id, 0..11)
    else
      id
    end
  end

  defp short_id(_), do: "?"
end
