defmodule Ichor.Activity.EventAnalysis do
  @moduledoc """
  Event analysis functions for tool analytics and timeline computation.
  Centralizes Pre/PostToolUse pairing and event aggregation.
  """

  @doc """
  Compute tool performance analytics from events.
  Groups by tool name, calculates success/failure rates and average durations.
  """
  def tool_analytics(events) do
    tool_events =
      Enum.filter(events, fn e ->
        e.hook_event_type in [:PreToolUse, :PostToolUse, :PostToolUseFailure]
      end)

    tool_events
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool, evts} ->
      completions =
        Enum.filter(evts, &(&1.hook_event_type in [:PostToolUse, :PostToolUseFailure]))

      failures = Enum.filter(completions, &(&1.hook_event_type == :PostToolUseFailure))
      successes = Enum.filter(completions, &(&1.hook_event_type == :PostToolUse))

      durations =
        successes
        |> Enum.map(& &1.duration_ms)
        |> Enum.reject(&is_nil/1)

      avg_duration =
        if Enum.empty?(durations),
          do: nil,
          else: Float.round(Enum.sum(durations) / length(durations), 1)

      %{
        tool: tool,
        total_uses: length(completions),
        successes: length(successes),
        failures: length(failures),
        failure_rate:
          if(completions != [],
            do: Float.round(length(failures) / length(completions), 2),
            else: 0.0
          ),
        avg_duration_ms: avg_duration
      }
    end)
    |> Enum.sort_by(& &1.total_uses, :desc)
  end

  @doc """
  Compute timeline data from events grouped by session.
  Returns a list of session timelines with tool blocks and idle gaps.
  """
  def timeline(events) do
    events
    |> Enum.group_by(& &1.session_id)
    |> Enum.map(fn {session_id, session_events} ->
      sorted_events = Enum.sort_by(session_events, & &1.inserted_at, {:asc, DateTime})
      blocks = build_timeline_blocks(sorted_events)

      first_event = List.first(sorted_events)
      last_event = List.last(sorted_events)

      %{
        session_id: session_id,
        source_app: first_event.source_app,
        blocks: blocks,
        start_time: first_event.inserted_at,
        end_time: last_event.inserted_at,
        duration_sec: DateTime.diff(last_event.inserted_at, first_event.inserted_at, :second)
      }
    end)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  @doc """
  Pair PreToolUse events with their PostToolUse/PostToolUseFailure counterparts.
  Shared pairing logic used by feed, timeline, and analytics.
  """
  def pair_tool_events(events) do
    post_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure] and e.tool_use_id
      end)
      |> Map.new(fn e -> {e.tool_use_id, e} end)

    events
    |> Enum.filter(fn e -> e.hook_event_type == :PreToolUse and e.tool_use_id end)
    |> Enum.map(fn pre ->
      post = Map.get(post_events, pre.tool_use_id)

      %{
        pre: pre,
        post: post,
        duration_ms: if(post, do: post.duration_ms, else: nil),
        status: determine_status(post),
        tool_use_id: pre.tool_use_id,
        tool_name: pre.tool_name
      }
    end)
  end

  # ── Timeline helpers ──────────────────────────────────────────

  defp build_timeline_blocks(events) do
    post_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PostToolUse, :PostToolUseFailure] and e.tool_use_id
      end)
      |> Map.new(fn e -> {e.tool_use_id, e} end)

    pre_events =
      Enum.filter(events, fn e ->
        e.hook_event_type == :PreToolUse and e.tool_use_id
      end)

    blocks =
      Enum.map(pre_events, fn pre ->
        post = Map.get(post_events, pre.tool_use_id)

        %{
          tool_use_id: pre.tool_use_id,
          tool_name: pre.tool_name,
          start_time: pre.inserted_at,
          end_time: if(post, do: post.inserted_at, else: pre.inserted_at),
          duration_ms: if(post, do: post.duration_ms, else: nil),
          status: determine_status(post),
          summary: event_summary(pre),
          event_id: pre.id
        }
      end)

    add_idle_gaps(blocks, events)
  end

  defp determine_status(nil), do: :in_progress
  defp determine_status(%{hook_event_type: :PostToolUse}), do: :success
  defp determine_status(%{hook_event_type: :PostToolUseFailure}), do: :failure
  defp determine_status(_), do: :unknown

  defp event_summary(pre) do
    input = (pre.payload || %{})["tool_input"] || %{}

    case pre.tool_name do
      "Bash" -> truncate(input["command"] || "", 60)
      "Read" -> Path.basename(input["file_path"] || "")
      "Write" -> Path.basename(input["file_path"] || "")
      "Edit" -> Path.basename(input["file_path"] || "")
      "Grep" -> "grep: #{truncate(input["pattern"] || "", 30)}"
      "Glob" -> "glob: #{truncate(input["pattern"] || "", 30)}"
      "Task" -> truncate(input["description"] || "", 50)
      "WebSearch" -> truncate(input["query"] || "", 40)
      "SendMessage" -> "msg: #{input["recipient"] || "?"}"
      "TaskCreate" -> truncate(input["subject"] || "", 40)
      _ -> pre.tool_name || "?"
    end
  end

  defp truncate(str, max) when is_binary(str) and byte_size(str) > max do
    String.slice(str, 0, max) <> "..."
  end

  defp truncate(str, _max) when is_binary(str), do: str
  defp truncate(_, _), do: ""

  defp add_idle_gaps(blocks, all_events) do
    sorted_blocks = Enum.sort_by(blocks, & &1.start_time, {:asc, DateTime})

    if Enum.empty?(sorted_blocks) do
      []
    else
      session_start = List.first(all_events).inserted_at
      session_end = List.last(all_events).inserted_at

      result = []

      first_block = List.first(sorted_blocks)

      result =
        if DateTime.compare(session_start, first_block.start_time) == :lt do
          [%{type: :idle, start_time: session_start, end_time: first_block.start_time} | result]
        else
          result
        end

      result =
        sorted_blocks
        |> Enum.reduce(result, fn block, acc ->
          prev_end =
            if Enum.empty?(acc), do: session_start, else: List.first(acc).end_time

          acc =
            if DateTime.compare(prev_end, block.start_time) == :lt do
              [%{type: :idle, start_time: prev_end, end_time: block.start_time} | acc]
            else
              acc
            end

          [Map.put(block, :type, :tool) | acc]
        end)

      last_block = List.first(result)

      result =
        if last_block && DateTime.compare(last_block.end_time, session_end) == :lt do
          [%{type: :idle, start_time: last_block.end_time, end_time: session_end} | result]
        else
          result
        end

      Enum.reverse(result)
    end
  end
end
