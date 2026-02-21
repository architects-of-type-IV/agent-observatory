defmodule ObservatoryWeb.DashboardFeedHelpers do
  @moduledoc """
  Feed grouping and event pairing helpers for the Observatory Dashboard.
  Groups events by session, then by conversation turns (UserPromptSubmit/Stop boundaries),
  then by activity phases (consecutive tools of the same category).
  """

  # ═══════════════════════════════════════════════════════
  # Public API
  # ═══════════════════════════════════════════════════════

  @doc """
  Build grouped feed structure with turns, agent names, and full metadata.
  Each session group contains turns: conversation turns with activity phases.
  """
  def build_feed_groups(events, teams \\ []) do
    name_map = build_agent_name_map(events, teams)

    events
    |> group_events_by_session()
    |> Enum.map(fn {session_id, session_events} ->
      build_session_group(session_id, session_events, name_map)
    end)
    |> Enum.sort_by(& &1.start_time, {:desc, DateTime})
  end

  def elapsed_time_ms(pre_event, now \\ DateTime.utc_now()) do
    DateTime.diff(now, pre_event.inserted_at, :millisecond)
  end

  @doc """
  Summarize tool names in a list of pairs for a collapsed header.
  Returns string like "Read x3, Edit x1, Bash x1"
  """
  def chain_tool_summary(pairs) do
    pairs
    |> Enum.frequencies_by(& &1.tool_name)
    |> Enum.sort_by(fn {_name, count} -> -count end)
    |> Enum.map(fn {name, count} ->
      if count == 1, do: name, else: "#{name} x#{count}"
    end)
    |> Enum.join(", ")
  end

  @doc """
  Total duration of a list of tool pairs in milliseconds.
  """
  def chain_total_duration(pairs) do
    pairs
    |> Enum.map(& &1.duration_ms)
    |> Enum.reject(&is_nil/1)
    |> case do
      [] -> nil
      durations -> Enum.sum(durations)
    end
  end

  @doc """
  Overall status of a list of tool pairs.
  """
  def chain_status(pairs) do
    cond do
      Enum.any?(pairs, &(&1.status == :in_progress)) -> :in_progress
      Enum.any?(pairs, &(&1.status == :failure)) -> :has_failures
      Enum.all?(pairs, &(&1.status == :success)) -> :success
      true -> :mixed
    end
  end

  # ═══════════════════════════════════════════════════════
  # Tool classification
  # ═══════════════════════════════════════════════════════

  @doc """
  Classify a tool name into an activity phase category.
  """
  def classify_tool("Read"), do: :research
  def classify_tool("Grep"), do: :research
  def classify_tool("Glob"), do: :research
  def classify_tool("WebSearch"), do: :research
  def classify_tool("WebFetch"), do: :research
  def classify_tool("Edit"), do: :build
  def classify_tool("Write"), do: :build
  def classify_tool("NotebookEdit"), do: :build
  def classify_tool("Bash"), do: :verify
  def classify_tool("Task"), do: :delegate
  def classify_tool("TaskOutput"), do: :delegate
  def classify_tool("TeamCreate"), do: :delegate
  def classify_tool("TeamDelete"), do: :delegate
  def classify_tool("SendMessage"), do: :communicate
  def classify_tool("AskUserQuestion"), do: :communicate
  def classify_tool("mcp__sequential-thinking" <> _), do: :think
  def classify_tool(_), do: :other

  # ═══════════════════════════════════════════════════════
  # Turn builder -- splits session events by conversation turn boundaries
  # ═══════════════════════════════════════════════════════

  @doc """
  Build conversation turns from sorted session events.
  Splits at UserPromptSubmit/Stop boundaries.

  Returns a list of:
    %{type: :turn, ...}           -- a conversation turn
    %{type: :preamble, ...}       -- events before first UserPromptSubmit
    %{type: :subagent_stop, ...}  -- orphan SubagentStop between turns
  """
  def build_turns(sorted_events) do
    perm_map = build_permission_lookup(sorted_events)

    tool_pairs =
      sorted_events
      |> pair_tool_events()
      |> attach_permissions(perm_map)

    pair_map = build_pair_lookup(tool_pairs)

    {items, current_turn} =
      sorted_events
      |> Enum.reduce({[], nil}, fn event, {items, current_turn} ->
        case event.hook_event_type do
          :UserPromptSubmit ->
            # Flush any in-progress turn
            items = flush_turn(items, current_turn)

            prompt_text =
              case event.payload do
                %{"prompt" => p} when is_binary(p) -> p
                _ -> ""
              end

            new_turn = %{
              type: :turn,
              prompt: prompt_text,
              prompt_event: event,
              response: nil,
              stop_event: nil,
              events: [event],
              tool_pairs: [],
              first_event_id: event.id
            }

            {items, new_turn}

          :Stop ->
            if current_turn do
              # Check if this is a subagent stop (orphan) or the turn's stop
              response_text =
                case event.payload do
                  %{"last_assistant_message" => msg} when is_binary(msg) -> msg
                  _ -> nil
                end

              # If we already have a stop (subagent stop within turn), just accumulate
              if current_turn.stop_event do
                updated = %{current_turn | events: current_turn.events ++ [event]}
                {items, updated}
              else
                updated = %{
                  current_turn
                  | response: response_text || current_turn.response,
                    stop_event: event,
                    events: current_turn.events ++ [event]
                }

                {items, updated}
              end
            else
              # Orphan stop outside any turn
              {items ++ [%{type: :subagent_stop, event: event}], nil}
            end

          :SubagentStop ->
            if current_turn do
              updated = %{current_turn | events: current_turn.events ++ [event]}
              {items, updated}
            else
              agent_id = (event.payload || %{})["agent_id"]

              {items ++
                 [
                   %{
                     type: :subagent_stop,
                     event: event,
                     agent_id: agent_id
                   }
                 ], nil}
            end

          _ ->
            if current_turn do
              # Accumulate tool pairs for this turn
              tool_pair =
                if event.hook_event_type == :PreToolUse && event.tool_use_id do
                  Map.get(pair_map, event.tool_use_id)
                end

              updated =
                if tool_pair do
                  %{
                    current_turn
                    | events: current_turn.events ++ [event],
                      tool_pairs: current_turn.tool_pairs ++ [tool_pair]
                  }
                else
                  %{current_turn | events: current_turn.events ++ [event]}
                end

              {items, updated}
            else
              # Pre-turn preamble event -- also accumulate tool pairs
              tool_pair =
                if event.hook_event_type == :PreToolUse && event.tool_use_id do
                  Map.get(pair_map, event.tool_use_id)
                end

              case items do
                [%{type: :preamble} = preamble | rest] ->
                  updated = %{preamble | events: preamble.events ++ [event]}
                  updated = if tool_pair, do: %{updated | tool_pairs: updated.tool_pairs ++ [tool_pair]}, else: updated
                  {[updated | rest], nil}

                _ ->
                  preamble = %{type: :preamble, events: [event], tool_pairs: if(tool_pair, do: [tool_pair], else: [])}
                  {items ++ [preamble], nil}
              end
            end
        end
      end)

    # Flush the last turn
    items = flush_turn(items, current_turn)

    # Enrich turns with phases
    Enum.map(items, fn
      %{type: :turn} = turn ->
        phases = group_into_phases(turn.tool_pairs)

        total_duration =
          turn.tool_pairs
          |> Enum.map(& &1.duration_ms)
          |> Enum.reject(&is_nil/1)
          |> case do
            [] -> nil
            durations -> Enum.sum(durations)
          end

        permission_count =
          turn.tool_pairs
          |> Enum.flat_map(fn p -> p[:permission_events] || [] end)
          |> length()

        Map.merge(turn, %{
          phases: phases,
          tool_count: length(turn.tool_pairs),
          total_duration_ms: total_duration,
          permission_count: permission_count,
          start_time: turn.prompt_event.inserted_at,
          end_time:
            if(turn.stop_event, do: turn.stop_event.inserted_at, else: turn.prompt_event.inserted_at)
        })

      %{type: :preamble} = preamble ->
        phases = group_into_phases(preamble.tool_pairs)

        total_duration =
          preamble.tool_pairs
          |> Enum.map(& &1.duration_ms)
          |> Enum.reject(&is_nil/1)
          |> case do
            [] -> nil
            durations -> Enum.sum(durations)
          end

        first_event = List.first(preamble.events)

        Map.merge(preamble, %{
          phases: phases,
          tool_count: length(preamble.tool_pairs),
          total_duration_ms: total_duration,
          start_time: first_event && first_event.inserted_at
        })

      other ->
        other
    end)
  end

  @doc """
  Group consecutive tool pairs by their classified phase.
  Returns: [%{phase: :research, pairs: [...], duration_ms: N, permission_count: N}, ...]
  """
  def group_into_phases(tool_pairs) do
    tool_pairs
    |> Enum.reduce([], fn pair, acc ->
      phase = classify_tool(pair.tool_name)

      case acc do
        [%{phase: ^phase} = current | rest] ->
          [%{current | pairs: current.pairs ++ [pair]} | rest]

        _ ->
          [%{phase: phase, pairs: [pair]} | acc]
      end
    end)
    |> Enum.reverse()
    |> Enum.with_index()
    |> Enum.map(fn {phase_group, index} ->
      perm_count =
        phase_group.pairs
        |> Enum.flat_map(fn p -> p[:permission_events] || [] end)
        |> length()

      Map.merge(phase_group, %{
        index: index,
        duration_ms: chain_total_duration(phase_group.pairs),
        status: chain_status(phase_group.pairs),
        permission_count: perm_count,
        tool_summary: chain_tool_summary(phase_group.pairs)
      })
    end)
  end

  # ═══════════════════════════════════════════════════════
  # Session group builder
  # ═══════════════════════════════════════════════════════

  defp group_events_by_session(events) do
    Enum.group_by(events, & &1.session_id)
  end

  defp build_session_group(session_id, events, name_map) do
    sorted = Enum.sort_by(events, & &1.inserted_at, {:asc, DateTime})

    session_start = Enum.find(sorted, &(&1.hook_event_type == :SessionStart))
    session_end = Enum.find(sorted, &(&1.hook_event_type == :SessionEnd))

    first_event = List.first(sorted)
    last_event = List.last(sorted)

    has_subagents = Enum.any?(sorted, &(&1.hook_event_type == :SubagentStart))
    turns = build_turns(sorted)

    role =
      cond do
        has_subagents -> :lead
        true -> :standalone
      end

    subagent_count =
      sorted |> Enum.count(&(&1.hook_event_type == :SubagentStop))

    turn_count = Enum.count(turns, fn t -> t.type == :turn end)

    total_duration_ms =
      if session_start && session_end,
        do: DateTime.diff(session_end.inserted_at, session_start.inserted_at, :millisecond)

    %{
      session_id: session_id,
      agent_name: Map.get(name_map, session_id),
      role: role,
      events: sorted,
      turns: Enum.reverse(turns),
      turn_count: turn_count,
      session_start: session_start,
      session_end: session_end,
      stop_event: Enum.find(Enum.reverse(sorted), &(&1.hook_event_type == :Stop)),
      model: extract_model(sorted),
      cwd: extract_cwd(sorted),
      permission_mode: extract_permission_mode(sorted),
      source_app: first_event && first_event.source_app,
      event_count: length(sorted),
      tool_count: sorted |> Enum.count(&(&1.hook_event_type == :PreToolUse)),
      subagent_count: subagent_count,
      total_duration_ms: total_duration_ms,
      start_time:
        if(session_start, do: session_start.inserted_at, else: first_event && first_event.inserted_at),
      end_time:
        cond do
          session_end -> session_end.inserted_at
          true -> last_event && last_event.inserted_at
        end,
      is_active: session_end == nil
    }
  end

  # ═══════════════════════════════════════════════════════
  # Turn builder helpers
  # ═══════════════════════════════════════════════════════

  defp flush_turn(items, nil), do: items
  defp flush_turn(items, turn), do: items ++ [turn]

  defp build_pair_lookup(tool_pairs) do
    Map.new(tool_pairs, fn pair -> {pair.tool_use_id, pair} end)
  end

  defp build_permission_lookup(events) do
    events
    |> Enum.filter(fn e ->
      e.hook_event_type in [:PermissionRequest, :Notification] and e.tool_use_id
    end)
    |> Enum.group_by(& &1.tool_use_id)
  end

  defp attach_permissions(tool_pairs, perm_map) do
    Enum.map(tool_pairs, fn pair ->
      perms = Map.get(perm_map, pair.tool_use_id, [])

      {permission_events, notification_events} =
        Enum.split_with(perms, fn e -> e.hook_event_type == :PermissionRequest end)

      Map.merge(pair, %{
        permission_events: permission_events,
        notification_events: notification_events
      })
    end)
  end

  # ═══════════════════════════════════════════════════════
  # Agent name resolution
  # ═══════════════════════════════════════════════════════

  defp build_agent_name_map(events, teams) do
    team_names =
      teams
      |> Enum.flat_map(fn team ->
        (team[:members] || [])
        |> Enum.flat_map(fn m ->
          entries = []
          entries = if m[:session_id], do: [{m[:session_id], m[:name]}] ++ entries, else: entries
          entries = if m[:agent_id], do: [{m[:agent_id], m[:name]}] ++ entries, else: entries
          entries
        end)
      end)
      |> Map.new()

    session_start_names =
      events
      |> Enum.filter(&(&1.hook_event_type == :SessionStart))
      |> Enum.reduce(%{}, fn e, acc ->
        cwd = e.cwd
        name = if cwd && cwd != "", do: Path.basename(cwd), else: nil

        if name && !Map.has_key?(acc, e.session_id),
          do: Map.put(acc, e.session_id, name),
          else: acc
      end)

    Map.merge(session_start_names, team_names)
  end

  # ═══════════════════════════════════════════════════════
  # Tool pairing
  # ═══════════════════════════════════════════════════════

  defp pair_tool_events(events) do
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

  defp determine_status(nil), do: :in_progress
  defp determine_status(%{hook_event_type: :PostToolUse}), do: :success
  defp determine_status(%{hook_event_type: :PostToolUseFailure}), do: :failure
  defp determine_status(_), do: :unknown

  # ═══════════════════════════════════════════════════════
  # Metadata extraction
  # ═══════════════════════════════════════════════════════

  defp extract_model(events) do
    session_start = Enum.find(events, &(&1.hook_event_type == :SessionStart))

    cond do
      session_start && is_map(session_start.payload) ->
        session_start.payload["model"] || session_start.model_name

      true ->
        Enum.find_value(events, fn e -> e.model_name || (e.payload || %{})["model"] end)
    end
  end

  defp extract_cwd(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.cwd end)
  end

  defp extract_permission_mode(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.permission_mode end)
  end
end
