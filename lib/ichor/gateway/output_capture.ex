defmodule Ichor.Gateway.OutputCapture do
  @moduledoc """
  Polls tmux pane output for watched agents and broadcasts changes.
  Extracted from AgentRegistry -- single responsibility: terminal output streaming.
  """

  use GenServer
  require Logger

  alias Ichor.Control.AgentProcess
  alias Ichor.Infrastructure.Tmux

  @capture_poll_interval 1_500

  @doc "Start the OutputCapture GenServer."
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc "Start watching an agent for terminal output."
  @spec watch(String.t()) :: :ok
  def watch(session_id) do
    GenServer.cast(__MODULE__, {:watch, session_id})
  end

  @doc "Stop watching an agent for terminal output."
  @spec unwatch(String.t()) :: :ok
  def unwatch(session_id) do
    GenServer.cast(__MODULE__, {:unwatch, session_id})
  end

  @impl true
  def init(_opts) do
    {:ok, %{watched: MapSet.new(), last_capture: %{}}}
  end

  @impl true
  def handle_cast({:watch, session_id}, state) do
    new_watched = MapSet.put(state.watched, session_id)

    if MapSet.size(state.watched) == 0 do
      schedule_poll()
    end

    {:noreply, %{state | watched: new_watched}}
  end

  def handle_cast({:unwatch, session_id}, state) do
    {:noreply, %{state | watched: MapSet.delete(state.watched, session_id)}}
  end

  @impl true
  def handle_info(:poll_capture, state) do
    new_last = capture_watched(state.watched, state.last_capture)

    if MapSet.size(state.watched) > 0 do
      schedule_poll()
    end

    {:noreply, %{state | last_capture: sweep_stale(state.watched, new_last)}}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  defp capture_watched(watched, last_capture) do
    Enum.reduce(watched, last_capture, fn session_id, acc ->
      tmux_target =
        case AgentProcess.lookup(session_id) do
          {_pid, %{channels: %{tmux: target}}} when is_binary(target) -> target
          _ -> nil
        end

      capture_session(session_id, tmux_target, acc)
    end)
  end

  defp capture_session(_session_id, nil, acc), do: acc

  defp capture_session(session_id, tmux_target, acc) do
    case Tmux.capture_pane(tmux_target) do
      {:ok, output} -> maybe_emit_output(session_id, output, acc)
      {:error, _} -> acc
    end
  end

  defp maybe_emit_output(session_id, output, acc) do
    prev = Map.get(acc, session_id, "")

    if output != prev do
      Ichor.Signals.emit(:terminal_output, session_id, %{session_id: session_id, output: output})
      Map.put(acc, session_id, output)
    else
      acc
    end
  end

  defp sweep_stale(watched, last_capture) do
    Map.filter(last_capture, fn {sid, _} -> MapSet.member?(watched, sid) end)
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_capture, @capture_poll_interval)
  end
end
