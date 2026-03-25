defmodule Ichor.Projector.TeamSpawnHandler do
  @moduledoc """
  Signal-driven team launch worker.

  Listens for team spawn requests and performs tmux/session creation in a
  decoupled process, then emits scoped completion signals for the caller.
  """

  use GenServer

  alias Ichor.Events
  alias Ichor.Events.Event
  alias Ichor.Orchestration.TeamLaunch
  alias Ichor.Orchestration.TeamSpec

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Ichor.Events.subscribe_all()
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        %Event{
          topic: "fleet.team.spawn_requested",
          data: %{scope_id: request_id, spec: %TeamSpec{} = spec, source: source}
        },
        state
      ) do
    emit_started(request_id, spec, source)

    case TeamLaunch.launch(spec) do
      {:ok, session} ->
        Events.emit(
          Event.new(
            "fleet.team.spawn_ready",
            request_id,
            %{
              scope_id: request_id,
              session: session,
              team_name: spec.team_name,
              agent_count: length(spec.agents),
              source: source
            },
            %{legacy_name: :team_spawn_ready}
          )
        )

      {:error, reason} ->
        Events.emit(
          Event.new(
            "fleet.team.spawn_failed",
            request_id,
            %{
              scope_id: request_id,
              team_name: spec.team_name,
              reason: inspect(reason),
              source: source
            },
            %{legacy_name: :team_spawn_failed}
          )
        )
    end

    {:noreply, state}
  end

  def handle_info(%Event{}, state), do: {:noreply, state}

  defp emit_started(request_id, spec, source) do
    Events.emit(
      Event.new(
        "fleet.team.spawn_started",
        request_id,
        %{
          scope_id: request_id,
          team_name: spec.team_name,
          agent_count: length(spec.agents),
          source: source
        },
        %{legacy_name: :team_spawn_started}
      )
    )
  end
end
