defmodule IchorWeb.DashboardAgentActivityHelpers do
  @moduledoc """
  Agent activity stream helpers for the Ichor Dashboard.
  Parses events into human-readable summaries and formats payloads.
  """

  @doc """
  Summarize a tool event into a human-readable description.
  Extracts key information from the payload based on tool_name and hook_event_type.
  """
  def summarize_event(%{hook_event_type: :SessionStart} = event) do
    model = extract_model(event)
    "Session started (#{model})"
  end

  def summarize_event(%{hook_event_type: :SessionEnd}), do: "Session ended"
  def summarize_event(%{hook_event_type: :PreToolUse} = event), do: summarize_tool_use(event)

  def summarize_event(%{hook_event_type: :PostToolUse} = event),
    do: summarize_tool_completion(event)

  def summarize_event(%{hook_event_type: :PostToolUseFailure} = event),
    do: summarize_tool_failure(event)

  def summarize_event(%{hook_event_type: :UserPromptSubmit}), do: "User prompt submitted"
  def summarize_event(%{hook_event_type: :SubagentStart}), do: "Subagent spawned"
  def summarize_event(%{hook_event_type: :SubagentStop}), do: "Subagent stopped"
  def summarize_event(event), do: "#{event.hook_event_type}"

  defp summarize_tool_use(%{tool_name: "Read"} = event) do
    "Reading #{extract_file_path(tool_input(event))}"
  end

  defp summarize_tool_use(%{tool_name: "Write"} = event) do
    "Writing #{extract_file_path(tool_input(event))}"
  end

  defp summarize_tool_use(%{tool_name: "Edit"} = event) do
    "Editing #{extract_file_path(tool_input(event))}"
  end

  defp summarize_tool_use(%{tool_name: "Bash"} = event) do
    "Running `#{extract_command(tool_input(event))}`"
  end

  defp summarize_tool_use(%{tool_name: "Grep"} = event) do
    pattern = tool_input(event)["pattern"] || "?"
    "Searching for '#{pattern}'"
  end

  defp summarize_tool_use(%{tool_name: "Glob"} = event) do
    pattern = tool_input(event)["pattern"] || "?"
    "Finding files matching '#{pattern}'"
  end

  defp summarize_tool_use(%{tool_name: "Task"} = event) do
    input = tool_input(event)
    agent_type = input["subagent_type"] || input["agent_type"] || "agent"
    "Delegated to #{agent_type}"
  end

  defp summarize_tool_use(%{tool_name: "WebSearch"} = event) do
    query = tool_input(event)["query"] || "?"
    "Web search: #{query}"
  end

  defp summarize_tool_use(%{tool_name: "WebFetch"} = event) do
    url = tool_input(event)["url"] || "?"
    "Fetching #{url}"
  end

  defp summarize_tool_use(%{tool_name: "SendMessage"} = event) do
    recipient = tool_input(event)["recipient"] || "team"
    "Sending message to #{recipient}"
  end

  defp summarize_tool_use(%{tool_name: "TaskCreate"} = event) do
    subject = tool_input(event)["subject"] || "task"
    "Creating task: #{subject}"
  end

  defp summarize_tool_use(%{tool_name: "TaskUpdate"} = event) do
    input = tool_input(event)
    task_id = input["taskId"] || "?"
    status = input["status"]
    if status, do: "Updating task ##{task_id} (#{status})", else: "Updating task ##{task_id}"
  end

  defp summarize_tool_use(%{tool_name: "NotebookEdit"} = event) do
    notebook_path = extract_notebook_path(tool_input(event))
    "Editing notebook #{notebook_path}"
  end

  defp summarize_tool_use(%{tool_name: nil}), do: "Tool use"
  defp summarize_tool_use(event), do: "#{event.tool_name}"

  defp tool_input(event), do: get_in(event.payload, ["tool_input"]) || %{}

  defp summarize_tool_completion(event) do
    duration = format_duration(event.duration_ms)

    case event.tool_name do
      "Bash" ->
        "Completed `#{extract_command_from_payload(event.payload)}` (#{duration})"

      "Read" ->
        "Read #{extract_file_path_from_payload(event.payload)} (#{duration})"

      "Write" ->
        lines = extract_line_count(event.payload)
        "Wrote #{lines} lines (#{duration})"

      "Edit" ->
        "Edited file (#{duration})"

      nil ->
        "Tool completed (#{duration})"

      _ ->
        "#{event.tool_name} completed (#{duration})"
    end
  end

  defp summarize_tool_failure(%{tool_name: "Bash"} = event) do
    "Failed: `#{extract_command_from_payload(event.payload)}`"
  end

  defp summarize_tool_failure(%{tool_name: nil}), do: "Tool failed"
  defp summarize_tool_failure(event), do: "#{event.tool_name} failed"

  @doc """
  Format event payload as readable key-value pairs for inspection.
  """
  def format_payload_detail(event) do
    payload = event.payload || %{}

    # Extract commonly useful fields
    details =
      []
      |> maybe_add("Tool", event.tool_name)
      |> maybe_add("Event Type", event.hook_event_type)
      |> maybe_add("Duration", format_duration(event.duration_ms))
      |> maybe_add("Tool Use ID", event.tool_use_id)

    # Add payload fields
    payload_details =
      payload
      |> Map.drop(["hook_event_name", "session_id", "transcript_path"])
      |> Enum.map(fn {k, v} -> {k, format_value(v)} end)

    details ++ payload_details
  end

  defp maybe_add(list, _key, nil), do: list
  defp maybe_add(list, key, value), do: list ++ [{key, value}]

  defp format_value(v) when is_binary(v) and byte_size(v) > 200 do
    "#{String.slice(v, 0..197)}..."
  end

  defp format_value(v) when is_map(v), do: inspect(v, pretty: true, limit: 10)
  defp format_value(v) when is_list(v), do: inspect(v, pretty: true, limit: 10)
  defp format_value(v), do: to_string(v)

  @doc """
  Filter events to those belonging to a specific agent session.
  """
  def agent_events(events, session_id) do
    events
    |> Enum.filter(&(&1.session_id == session_id))
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
  end

  # Extraction helpers

  defp extract_model(event) do
    event.model_name || get_in(event.payload, ["model"]) || "unknown"
  end

  defp extract_file_path(tool_input) do
    tool_input["file_path"] || tool_input["notebook_path"] || "?"
  end

  defp extract_notebook_path(tool_input) do
    path = tool_input["notebook_path"] || "?"
    Path.basename(path)
  end

  defp extract_command(tool_input) do
    cmd = tool_input["command"] || "?"
    if String.length(cmd) > 60, do: String.slice(cmd, 0..57) <> "...", else: cmd
  end

  defp extract_command_from_payload(payload) do
    cmd = get_in(payload, ["tool_input", "command"]) || "?"
    if String.length(cmd) > 60, do: String.slice(cmd, 0..57) <> "...", else: cmd
  end

  defp extract_file_path_from_payload(payload) do
    path = get_in(payload, ["tool_input", "file_path"]) || "?"
    Path.basename(path)
  end

  defp extract_line_count(payload) do
    content = get_in(payload, ["tool_input", "content"])

    if content && is_binary(content) do
      line_count = content |> String.split("\n") |> length()
      "#{line_count}"
    else
      "unknown"
    end
  end

  defp format_duration(nil), do: nil
  defp format_duration(ms) when ms < 1000, do: "#{ms}ms"

  defp format_duration(ms) do
    secs = ms / 1000

    if secs < 60,
      do: "#{Float.round(secs, 1)}s",
      else: "#{div(ms, 60_000)}m#{rem(div(ms, 1000), 60)}s"
  end
end
