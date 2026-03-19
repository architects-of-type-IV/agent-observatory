defmodule Ichor.Mes.ResearchIngestor do
  @moduledoc """
  Subscribes to MES signals and ingests completed project briefs into
  the Memories knowledge graph. Fires on `:mes_project_created`, reads
  the brief from disk, and calls MemoriesClient.ingest/2.

  All episodes are scoped to space "project:ichor:research".
  """

  use GenServer

  require Logger

  alias Ichor.Archon.MemoriesClient
  alias Ichor.Mes
  alias Ichor.Signals
  alias Ichor.Signals.Message

  @research_space "project:ichor:research"
  @briefs_dir "subsystems/briefs"

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:mes)
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Message{name: :mes_project_created, data: data}, state) do
    ingest_research(data)
    {:noreply, state}
  end

  def handle_info(%Message{}, state), do: {:noreply, state}

  defp ingest_research(%{project_id: project_id, run_id: run_id} = data) do
    project = load_project(project_id)
    brief_text = read_brief(run_id)
    episode_text = build_episode(data, project, brief_text)

    case MemoriesClient.ingest(episode_text,
           space: @research_space,
           source: "mes-factory",
           type: "text"
         ) do
      {:ok, result} ->
        episode_id = extract_episode_id(result)

        Logger.info(
          "[MES.ResearchIngestor] Ingested research for #{data[:title]} (episode: #{episode_id})"
        )

        Signals.emit(:mes_research_ingested, %{
          run_id: run_id,
          project_id: project_id,
          episode_id: episode_id
        })

      {:error, reason} ->
        Logger.warning(
          "[MES.ResearchIngestor] Ingest failed for run #{run_id}: #{inspect(reason)}"
        )

        Signals.emit(:mes_research_ingest_failed, %{
          run_id: run_id,
          reason: inspect(reason)
        })
    end
  end

  defp load_project(project_id) do
    case Mes.get_project(project_id) do
      {:ok, project} -> project
      _ -> nil
    end
  end

  defp read_brief(run_id) do
    path = Path.join(@briefs_dir, "#{run_id}.md")

    case File.read(path) do
      {:ok, content} -> content
      {:error, _} -> nil
    end
  end

  defp build_episode(data, project, brief_text) do
    title = data[:title] || "Untitled"

    sections =
      [
        "MES Research Brief: #{title} (run #{data[:run_id]})",
        "",
        project_section(project),
        brief_section(brief_text)
      ]
      |> List.flatten()
      |> Enum.join("\n")

    String.trim(sections)
  end

  defp project_section(nil), do: []

  defp project_section(project) do
    fields = [
      {"Proposed subsystem", project.subsystem},
      {"Description", project.description},
      {"Topic", project.topic},
      {"Version", project.version},
      {"Signal interface", project.signal_interface},
      {"Architecture", project.architecture},
      {"Features", join_list(project.features)},
      {"Use cases", join_list(project.use_cases)},
      {"Dependencies", join_list(project.dependencies)},
      {"Signals emitted", join_list(project.signals_emitted)},
      {"Signals subscribed", join_list(project.signals_subscribed)}
    ]

    Enum.flat_map(fields, fn
      {_label, nil} -> []
      {_label, ""} -> []
      {label, value} -> ["#{label}: #{value}"]
    end)
  end

  defp brief_section(nil), do: []

  defp brief_section(text) do
    truncated = String.slice(text, 0, 3000)
    ["", "--- Researcher Notes ---", truncated]
  end

  defp join_list(nil), do: nil
  defp join_list([]), do: nil
  defp join_list(items) when is_list(items), do: Enum.join(items, ", ")
  defp join_list(other), do: other

  defp extract_episode_id(%MemoriesClient.IngestResult{episode_id: id}), do: id

  defp extract_episode_id(%MemoriesClient.ChunkedIngestResult{episodes: [first | _]}),
    do: first.episode_id

  defp extract_episode_id(_), do: "unknown"
end
