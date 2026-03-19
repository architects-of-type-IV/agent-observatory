defmodule Ichor.Mes.ProjectIngestor do
  @moduledoc """
  Subscribes to the messaging signal stream and detects MES project
  creation payloads from coordinator agents. Creates the Ash resource
  and emits :mes_project_created.

  Accepts two formats:
    1. JSON with `{"action":"create_mes_project",...}` (structured)
    2. Plain text with `TITLE:`, `SUBSYSTEM:`, etc. key-value lines (agent output)

  Messages arrive with atom keys from Delivery.normalize/2.
  Only processes messages sent TO "operator" FROM "mes-*" sessions.
  """

  use GenServer

  import Ichor.MapHelpers, only: [maybe_put: 3]

  require Logger

  alias Ichor.Mes
  alias Ichor.Signals

  @required_keys ~w(title description subsystem signal_interface)
  @all_keys ~w(title description subsystem signal_interface topic version
               features use_cases architecture dependencies
               signals_emitted signals_subscribed)

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:messages)
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Ichor.Signals.Message{name: :message_delivered, data: data}, state) do
    case extract_mes_payload(data) do
      {:ok, payload} -> ingest_project(payload, data)
      :skip -> :ok
    end

    {:noreply, state}
  end

  def handle_info(%Ichor.Signals.Message{}, state), do: {:noreply, state}

  # Normalized messages use :to and :from (atom keys), not :to_session_id
  defp extract_mes_payload(%{msg_map: %{to: "operator", content: content} = msg})
       when is_binary(content) do
    from = msg[:from] || ""

    if String.starts_with?(from, "mes-") do
      extract_from_content(content, from)
    else
      :skip
    end
  end

  defp extract_mes_payload(_), do: :skip

  defp extract_from_content(content, from) do
    # Try JSON first
    case Jason.decode(content) do
      {:ok, %{"action" => "create_mes_project"} = payload} ->
        {:ok, payload}

      {:ok, map} when is_map(map) ->
        if has_required_keys?(map), do: {:ok, map}, else: try_plaintext(content, from)

      _ ->
        try_plaintext(content, from)
    end
  end

  defp try_plaintext(content, from) do
    parsed = parse_key_value_brief(content)

    if has_required_keys?(parsed) do
      # Derive run_id from the session name: "mes-{run_id}-coordinator"
      run_id = extract_run_id(from)
      {:ok, Map.put(parsed, "run_id", run_id)}
    else
      :skip
    end
  end

  defp has_required_keys?(map) do
    Enum.all?(@required_keys, fn k ->
      val = map[k]
      is_binary(val) and val != ""
    end)
  end

  @spec parse_key_value_brief(String.t()) :: map()
  defp parse_key_value_brief(text) do
    text
    |> String.split("\n")
    |> Enum.reduce({%{}, nil}, fn line, {acc, current_key} ->
      case parse_key_line(line) do
        {key, value} when key in @all_keys ->
          {Map.put(acc, key, clean_value(key, value)), key}

        nil ->
          maybe_append_continuation(acc, current_key, line)
      end
    end)
    |> elem(0)
    |> convert_list_fields()
  end

  defp maybe_append_continuation(acc, current_key, line) do
    if current_key && list_field?(current_key) && continuation_line?(line) do
      existing = Map.get(acc, current_key, "")

      appended =
        if existing == "", do: String.trim(line), else: existing <> ", " <> String.trim(line)

      {Map.put(acc, current_key, appended), current_key}
    else
      {acc, current_key}
    end
  end

  defp parse_key_line(line) do
    trimmed = String.trim(line)

    # Match "TITLE: value" or "SIGNAL_INTERFACE: value" patterns
    case Regex.run(~r/^([A-Z][A-Z_]+)\s*:\s*(.+)$/i, trimmed) do
      [_, key_raw, value] ->
        key = key_raw |> String.downcase() |> String.trim()
        if key in @all_keys, do: {key, String.trim(value)}, else: nil

      _ ->
        nil
    end
  end

  defp clean_value(_key, value) do
    value
    |> String.trim()
    |> String.trim("`")
    |> String.trim("\"")
  end

  @list_fields ~w(features use_cases dependencies signals_emitted signals_subscribed)

  defp list_field?(key), do: key in @list_fields

  defp continuation_line?(line) do
    trimmed = String.trim(line)
    trimmed != "" and not Regex.match?(~r/^---/, trimmed) and not Regex.match?(~r/^##/, trimmed)
  end

  defp convert_list_fields(map) do
    Enum.reduce(@list_fields, map, fn key, acc ->
      case Map.get(acc, key) do
        val when is_binary(val) and val != "" ->
          items =
            val
            |> String.split(~r/\s*,\s*/)
            |> Enum.map(&String.trim/1)
            |> Enum.reject(&(&1 == ""))

          Map.put(acc, key, items)

        _ ->
          acc
      end
    end)
  end

  defp extract_run_id(from_session) do
    case Regex.run(~r/^mes-([^-]+)/, from_session) do
      [_, run_id] -> run_id
      _ -> from_session
    end
  end

  defp ingest_project(payload, data) do
    from = get_in(data, [:msg_map, :from_session_id]) || ""
    run_id = payload["run_id"] || extract_run_id(from)

    attrs =
      %{
        title: payload["title"],
        description: payload["description"],
        subsystem: payload["subsystem"],
        signal_interface: payload["signal_interface"],
        run_id: run_id,
        team_name: "mes-#{run_id}"
      }
      |> maybe_put(:topic, payload["topic"])
      |> maybe_put(:version, payload["version"])
      |> maybe_put(:features, payload["features"])
      |> maybe_put(:use_cases, payload["use_cases"])
      |> maybe_put(:architecture, payload["architecture"])
      |> maybe_put(:dependencies, payload["dependencies"])
      |> maybe_put(:signals_emitted, payload["signals_emitted"])
      |> maybe_put(:signals_subscribed, payload["signals_subscribed"])

    case Mes.create_project(attrs) do
      {:ok, project} ->
        Logger.info("[MES.ProjectIngestor] Ingested project: #{project.title} (#{project.id})")

        Signals.emit(:mes_project_created, %{
          project_id: project.id,
          title: project.title,
          run_id: run_id
        })

      {:error, reason} ->
        Logger.warning("[MES.ProjectIngestor] Failed to ingest: #{inspect(reason)}")
    end
  end
end
