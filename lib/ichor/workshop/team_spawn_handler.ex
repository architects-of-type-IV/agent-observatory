defmodule Ichor.Workshop.TeamSpawnHandler do
  @moduledoc """
  Signal-driven team launch worker.

  Listens for team spawn requests and performs tmux/session creation in a
  decoupled process, then emits scoped completion signals for the caller.
  """

  use GenServer

  alias Ichor.Orchestration.TeamLaunch
  alias Ichor.Orchestration.TeamSpec
  alias Ichor.Signals

  @doc false
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    Signals.subscribe(:fleet)
    {:ok, %{}}
  end

  @impl true
  def handle_info(
        %Signals.Message{
          name: :team_spawn_requested,
          data: %{scope_id: request_id, spec: %TeamSpec{} = spec, source: source}
        },
        state
      ) do
    emit_started(request_id, spec, source)

    case TeamLaunch.launch(spec) do
      {:ok, session} ->
        Signals.emit(:team_spawn_ready, request_id, %{
          session: session,
          team_name: spec.team_name,
          agent_count: length(spec.agents),
          source: source
        })

      {:error, reason} ->
        Signals.emit(:team_spawn_failed, request_id, %{
          team_name: spec.team_name,
          reason: inspect(reason),
          source: source
        })
    end

    {:noreply, state}
  end

  def handle_info(%Signals.Message{}, state), do: {:noreply, state}

  defp emit_started(request_id, spec, source) do
    Signals.emit(:team_spawn_started, request_id, %{
      team_name: spec.team_name,
      agent_count: length(spec.agents),
      source: source
    })
  end
end
