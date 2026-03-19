defmodule Ichor.PaneMonitor do
  @moduledoc """
  Monitors tmux pane output for all active agents, regardless of vendor.

  Subscribes to the heartbeat and periodically captures pane output to detect:
    - `ICHOR_DONE: <summary>` -- agent signals task completion
    - `ICHOR_BLOCKED: <summary>` -- agent signals it needs help
    - Activity timestamps -- detect stale/idle agents
    - Error patterns -- surface crashes or failures

  This makes hookless agents (codex, aider, pi, local models, etc.) first-class
  citizens in the fleet. Any agent in a tmux session is observable.
  """
  use GenServer
  require Logger

  alias Ichor.Fleet.AgentProcess
  alias Ichor.Gateway.Channels.{SshTmux, Tmux}

  @capture_lines 30

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @doc "Get the last captured output for a session."
  @spec last_capture(String.t()) :: String.t() | nil
  def last_capture(session_name) do
    GenServer.call(__MODULE__, {:last_capture, session_name})
  end

  @impl true
  def init(_opts) do
    Ichor.Signals.subscribe(:heartbeat)
    {:ok, %{captures: %{}, signals: %{}}}
  end

  @impl true
  def handle_info(%Ichor.Signals.Message{name: :heartbeat}, state) do
    state = scan_all_agents(state)
    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}

  @impl true
  def handle_call({:last_capture, session_name}, _from, state) do
    {:reply, Map.get(state.captures, session_name), state}
  end

  defp scan_all_agents(state) do
    AgentProcess.list_all()
    |> Enum.map(fn {_id, meta} -> meta end)
    |> Enum.filter(&(&1[:status] == :active))
    |> Enum.reduce(state, &scan_active_agent/2)
  end

  defp scan_active_agent(agent, acc) do
    case resolve_capture_target(agent) do
      {target, capture_fn} -> scan_agent(agent, target, capture_fn, acc)
      _ -> acc
    end
  end

  defp resolve_capture_target(%{channels: %{tmux: target}} = _meta) when is_binary(target) do
    {target, &Tmux.capture_pane(&1, lines: @capture_lines)}
  end

  defp resolve_capture_target(%{channels: %{ssh_tmux: target}} = _meta) when is_binary(target) do
    {target, &SshTmux.capture_pane(&1, lines: @capture_lines)}
  end

  defp resolve_capture_target(_), do: nil

  defp scan_agent(agent, tmux_target, capture_fn, state) do
    case capture_fn.(tmux_target) do
      {:ok, output} ->
        prev_output = Map.get(state.captures, tmux_target, "")
        state = put_in(state.captures[tmux_target], output)

        # Only parse new output (diff against previous capture)
        new_lines = diff_output(prev_output, output)

        if new_lines != "" do
          parse_signals(agent, new_lines, state)
        else
          state
        end

      {:error, _} ->
        state
    end
  end

  defp diff_output(prev, current) do
    prev_lines = String.split(prev, "\n", trim: true)
    curr_lines = String.split(current, "\n", trim: true)

    # Take lines from current that weren't in prev (simple tail diff)
    overlap = length(prev_lines)

    if overlap > 0 && length(curr_lines) > overlap do
      curr_lines
      |> Enum.drop(overlap)
      |> Enum.join("\n")
    else
      if prev == current, do: "", else: current
    end
  end

  defp parse_signals(agent, text, state) do
    state = check_done_signal(agent, text, state)
    state = check_blocked_signal(agent, text, state)
    check_activity(agent, text, state)
  end

  defp check_done_signal(agent, text, state) do
    case Regex.run(~r/ICHOR_DONE:\s*(.+)/, text) do
      [_, summary] ->
        session_id = agent[:session_id] || agent[:id]
        signal_key = {session_id, :done}

        # Deduplicate: only fire once per signal
        if Map.get(state.signals, signal_key) != summary do
          Logger.info("PaneMonitor: DONE signal from #{agent[:id]}: #{summary}")

          Ichor.Signals.emit(:agent_done, %{
            session_id: session_id,
            summary: String.trim(summary)
          })

          put_in(state.signals[signal_key], summary)
        else
          state
        end

      nil ->
        state
    end
  end

  defp check_blocked_signal(agent, text, state) do
    case Regex.run(~r/ICHOR_BLOCKED:\s*(.+)/, text) do
      [_, reason] ->
        session_id = agent[:session_id] || agent[:id]
        signal_key = {session_id, :blocked}

        if Map.get(state.signals, signal_key) != reason do
          Logger.info("PaneMonitor: BLOCKED signal from #{agent[:id]}: #{reason}")

          Ichor.Signals.emit(:agent_blocked, %{
            session_id: session_id,
            reason: String.trim(reason)
          })

          put_in(state.signals[signal_key], reason)
        else
          state
        end

      nil ->
        state
    end
  end

  defp check_activity(agent, _text, state) do
    # Any new output means the agent is active -- update registry timestamp
    session_id = agent[:session_id] || agent[:id]

    if session_id do
      AgentProcess.update_fields(session_id, %{last_event_at: DateTime.utc_now()})
    end

    state
  end
end
