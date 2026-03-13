defmodule Ichor.Mes.ProjectIngestor do
  @moduledoc """
  Subscribes to the messaging signal stream and detects MES project
  creation payloads from coordinator agents. Creates the Ash resource
  and emits :mes_project_created.

  Listens for send_message payloads with `{"action":"create_mes_project",...}`.
  Messages arrive with atom keys from Delivery.normalize/2.
  """

  use GenServer

  alias Ichor.Mes.Project
  alias Ichor.Signals

  # ── Public API ──────────────────────────────────────────────────────

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  # ── GenServer Callbacks ─────────────────────────────────────────────

  @impl true
  def init(_opts) do
    Signals.subscribe(:messages)
    {:ok, %{}}
  end

  @impl true
  def handle_info(%Ichor.Signals.Message{name: :message_delivered, data: data}, state) do
    case extract_mes_payload(data) do
      {:ok, payload} -> ingest_project(payload)
      :skip -> :ok
    end

    {:noreply, state}
  end

  def handle_info(%Ichor.Signals.Message{}, state), do: {:noreply, state}

  # ── Private ─────────────────────────────────────────────────────────

  # Delivery.normalize/2 produces atom keys -- match on :content
  defp extract_mes_payload(%{msg_map: %{content: content}}) when is_binary(content) do
    case Jason.decode(content) do
      {:ok, %{"action" => "create_mes_project"} = payload} -> {:ok, payload}
      _ -> :skip
    end
  end

  defp extract_mes_payload(_), do: :skip

  defp ingest_project(payload) do
    attrs = %{
      title: payload["title"],
      description: payload["description"],
      subsystem: payload["subsystem"],
      signal_interface: payload["signal_interface"],
      run_id: payload["run_id"],
      team_name: "mes-#{payload["run_id"]}"
    }

    case Project.create(attrs) do
      {:ok, project} ->
        Signals.emit(:mes_project_created, %{
          project_id: project.id,
          title: project.title,
          run_id: project.run_id
        })

      {:error, _reason} ->
        :ok
    end
  end
end
