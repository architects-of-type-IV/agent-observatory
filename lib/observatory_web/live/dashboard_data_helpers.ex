defmodule ObservatoryWeb.DashboardDataHelpers do
  @moduledoc """
  Data derivation and filtering helpers for the Observatory Dashboard.
  Handles tasks, messages, and event filtering/search.
  """

  @doc """
  Derive task state from TaskCreate/TaskUpdate events.
  """
  def derive_tasks(events) do
    # Build task state from TaskCreate/TaskUpdate events
    task_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type == :PreToolUse and e.tool_name in ["TaskCreate", "TaskUpdate"]
      end)
      |> Enum.sort_by(& &1.inserted_at, {:asc, DateTime})

    Enum.reduce(task_events, %{}, fn e, acc ->
      input = (e.payload || %{})["tool_input"] || %{}

      case e.tool_name do
        "TaskCreate" ->
          id = map_size(acc) + 1 |> to_string()

          task = %{
            id: id,
            subject: input["subject"],
            description: input["description"],
            status: "pending",
            owner: nil,
            active_form: input["activeForm"],
            session_id: e.session_id,
            created_at: e.inserted_at
          }

          Map.put(acc, id, task)

        "TaskUpdate" ->
          task_id = input["taskId"]

          if task_id && Map.has_key?(acc, task_id) do
            task = acc[task_id]

            task =
              task
              |> maybe_put(:status, input["status"])
              |> maybe_put(:owner, input["owner"])
              |> maybe_put(:subject, input["subject"])

            Map.put(acc, task_id, task)
          else
            acc
          end

        _ ->
          acc
      end
    end)
    |> Map.values()
    |> Enum.sort_by(& &1.id)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, val), do: Map.put(map, key, val)

  @doc """
  Derive inter-agent messages from SendMessage events.
  """
  def derive_messages(events) do
    events
    |> Enum.filter(fn e ->
      e.hook_event_type == :PreToolUse and e.tool_name == "SendMessage"
    end)
    |> Enum.map(fn e ->
      input = (e.payload || %{})["tool_input"] || %{}

      %{
        id: e.id,
        sender_session: e.session_id,
        sender_app: e.source_app,
        type: input["type"] || "message",
        recipient: input["recipient"],
        content: input["content"] || input["summary"] || "",
        summary: input["summary"],
        timestamp: e.inserted_at
      }
    end)
  end

  @doc """
  Filter events based on assigns (source, session, type, search).
  """
  def filtered_events(assigns) do
    assigns.events
    |> maybe_filter(:source_app, assigns.filter_source_app)
    |> maybe_filter(:session_id, assigns.filter_session_id)
    |> maybe_filter(:hook_event_type, assigns.filter_event_type)
    |> search_events(assigns.search_feed)
  end

  defp search_events(events, q) when q in [nil, ""], do: events

  defp search_events(events, q) do
    terms = q |> String.downcase() |> String.split(~r/\s+/, trim: true)
    Enum.filter(events, &event_matches?(&1, terms))
  end

  defp event_matches?(event, terms) do
    searchable = event_searchable_text(event)
    Enum.all?(terms, &String.contains?(searchable, &1))
  end

  defp event_searchable_text(event) do
    input = (event.payload || %{})["tool_input"] || %{}

    [
      event.source_app,
      event.session_id,
      to_string(event.hook_event_type),
      event.tool_name,
      event.tool_use_id,
      event.summary,
      event.cwd,
      event.permission_mode,
      event.model_name,
      input["command"],
      input["file_path"],
      input["pattern"],
      input["query"],
      input["url"],
      input["description"],
      input["prompt"],
      input["subject"],
      input["content"],
      input["recipient"],
      input["team_name"],
      (event.payload || %{})["message"],
      (event.payload || %{})["prompt"],
      (event.payload || %{})["error"],
      (event.payload || %{})["agent_type"],
      (event.payload || %{})["notification_type"],
      (event.payload || %{})["reason"],
      (event.payload || %{})["model"]
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join(" ")
    |> String.downcase()
  end

  @doc """
  Filter sessions by search query.
  """
  def filtered_sessions(sessions, q) when q in [nil, ""], do: sessions

  def filtered_sessions(sessions, q) do
    terms = q |> String.downcase() |> String.split(~r/\s+/, trim: true)

    Enum.filter(sessions, fn s ->
      searchable =
        [s.source_app, s.session_id, s.model, s.cwd, s.permission_mode]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(" ")
        |> String.downcase()

      Enum.all?(terms, &String.contains?(searchable, &1))
    end)
  end

  defp maybe_filter(events, _field, nil), do: events

  defp maybe_filter(events, :hook_event_type, value) do
    atom_val = String.to_existing_atom(value)
    Enum.filter(events, &(&1.hook_event_type == atom_val))
  end

  defp maybe_filter(events, field, value) do
    Enum.filter(events, &(Map.get(&1, field) == value))
  end

  @doc """
  Convert blank string to nil for filter cleanup.
  """
  def blank_to_nil(""), do: nil
  def blank_to_nil(val), do: val

  @doc """
  Extract unique values for a field across events.
  """
  def unique_values(events, field) do
    events |> Enum.map(&Map.get(&1, field)) |> Enum.uniq() |> Enum.sort()
  end

  @doc """
  Derive active sessions from events with metadata.
  """
  def active_sessions(events) do
    events
    |> Enum.group_by(&{&1.source_app, &1.session_id})
    |> Enum.map(fn {{app, sid}, evts} ->
      sorted = Enum.sort_by(evts, & &1.inserted_at, {:desc, DateTime})
      latest = hd(sorted)
      ended? = Enum.any?(evts, &(&1.hook_event_type == :SessionEnd))

      %{
        source_app: app,
        session_id: sid,
        event_count: length(evts),
        latest_event: latest,
        first_event: List.last(sorted),
        ended?: ended?,
        model: find_model(evts),
        permission_mode: latest.permission_mode,
        cwd: latest.cwd || find_cwd(evts)
      }
    end)
    |> Enum.sort_by(& &1.latest_event.inserted_at, {:desc, DateTime})
  end

  defp find_model(events), do: Enum.find_value(events, fn e -> e.payload["model"] || e.model_name end)
  defp find_cwd(events), do: Enum.find_value(events, fn e -> e.cwd end)

  @doc """
  Extract error events (PostToolUseFailure) from events.
  """
  def extract_errors(events) do
    events
    |> Enum.filter(&(&1.hook_event_type == :PostToolUseFailure))
    |> Enum.map(fn e ->
      %{
        id: e.id,
        tool_name: e.tool_name,
        session_id: e.session_id,
        source_app: e.source_app,
        error: e.payload["error"] || "Unknown error",
        timestamp: e.inserted_at,
        tool_use_id: e.tool_use_id
      }
    end)
  end

  @doc """
  Group errors by tool name for summary view.
  """
  def group_errors(errors) do
    errors
    |> Enum.group_by(& &1.tool_name)
    |> Enum.map(fn {tool, errs} ->
      %{
        tool: tool,
        count: length(errs),
        latest: List.first(Enum.sort_by(errs, & &1.timestamp, {:desc, DateTime})),
        errors: errs
      }
    end)
    |> Enum.sort_by(& &1.count, :desc)
  end

  @doc """
  Compute tool performance analytics from events.
  """
  def compute_tool_analytics(events) do
    # Get all PreToolUse and PostToolUse/PostToolUseFailure events
    tool_events =
      events
      |> Enum.filter(fn e ->
        e.hook_event_type in [:PreToolUse, :PostToolUse, :PostToolUseFailure]
      end)

    # Group by tool name
    tool_events
    |> Enum.group_by(fn e -> e.tool_name end)
    |> Enum.map(fn {tool, evts} ->
      completions = Enum.filter(evts, &(&1.hook_event_type in [:PostToolUse, :PostToolUseFailure]))
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
        failure_rate: if(length(completions) > 0, do: Float.round(length(failures) / length(completions), 2), else: 0.0),
        avg_duration_ms: avg_duration
      }
    end)
    |> Enum.sort_by(& &1.total_uses, :desc)
  end
end
