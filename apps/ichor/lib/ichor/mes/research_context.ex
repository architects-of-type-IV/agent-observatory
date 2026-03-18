defmodule Ichor.Mes.ResearchContext do
  @moduledoc """
  Generates dynamic research context for MES researcher prompts.

  Queries the Project database and core subsystem list at call time
  to produce three prompt sections:
    - Existing subsystems (what is already built)
    - Open gaps (what the system cannot do yet)
    - Dead zones (concepts that have been tried and failed repeatedly)

  Pure function module. No state, no process, no cache.
  """

  alias Ichor.Mes.Project

  @core_subsystems [
    {"HITLRelay", "human-in-the-loop pause/resume gating"},
    {"NudgeEscalator", "stale agent detection + progressive nudging"}
  ]

  @gap_definitions [
    {"No outbound push (no webhooks, file writes, or local notifications)",
     ~w(Webhook Notifier Egress Relay Push)},
    {"No external signal subscription (no SSE/WebSocket out)",
     ~w(SSE WebSocket EventSource Stream SignalBridge)},
    {"No scheduled signals (no cron-like emitter)", ~w(Cron Scheduler Timer Periodic Clock)},
    {"No signal transformation (no enrich/filter/remap layer)",
     ~w(Enricher Filter Transform Remap Decorator)},
    {"No external bridges (no MQTT, AMQP, Redis, Kafka)",
     ~w(MQTT AMQP Redis Kafka Bridge RabbitMQ)},
    {"No file/report generation from signals", ~w(Report CSV Export File Generator Digest)},
    {"No sound/desktop notifications", ~w(Sound Desktop Alert Beep Notification)}
  ]

  @dead_zone_seeds [
    "Signal correlation / causal correlation",
    "Anomaly detection (EWMA, CUSUM, z-score)",
    "Entropy monitoring / scoring",
    "Self-healer / swarm self-healer",
    "Adaptive load balancing",
    "Execution ledger / run history"
  ]

  @dead_zone_threshold 2

  @pain_points [
    ~s("I want a local notification when a MES run finishes"),
    ~s("I want a daily summary of what the fleet did, written to disk"),
    ~s("I want a webhook to a self-hosted endpoint when an agent crashes"),
    ~s("I want signals forwarded to a local logging service"),
    ~s("I want a cron-like scheduler that emits signals on a schedule"),
    ~s("I want to replay a signal to test a subsystem"),
    ~s("I want dead tmux sessions auto-cleaned after N minutes"),
    ~s("I want to tag signals with metadata before they reach subscribers"),
    ~s("I want to throttle noisy signal categories"),
    ~s("I want a subsystem that bridges MQTT/AMQP/Redis into Signals")
  ]

  # ── Public API ──────────────────────────────────────────────────────

  @doc "Rendered existing subsystems section for prompt interpolation."
  @spec existing_subsystems() :: String.t()
  def existing_subsystems do
    loaded_projects()
    |> build_subsystem_list()
    |> render_lines()
  end

  @doc "Rendered open gaps section for prompt interpolation."
  @spec open_gaps() :: String.t()
  def open_gaps do
    loaded = loaded_projects()

    @gap_definitions
    |> reject_filled(loaded)
    |> render_lines()
  end

  @doc "Rendered dead zones section for prompt interpolation."
  @spec dead_zones() :: String.t()
  def dead_zones do
    all = all_projects()
    auto = auto_dead_zones(all)
    combined = Enum.uniq(@dead_zone_seeds ++ auto)
    render_lines(combined)
  end

  @doc "Rendered operator pain points for prompt interpolation."
  @spec pain_points() :: String.t()
  def pain_points, do: render_lines(@pain_points)

  # ── Private: Data Queries ───────────────────────────────────────────

  defp loaded_projects do
    case Project.by_status(:loaded) do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  defp all_projects do
    case Project.list_all() do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  # ── Private: Subsystems ─────────────────────────────────────────────

  defp build_subsystem_list(loaded) do
    core_lines = Enum.map(@core_subsystems, fn {name, desc} -> "#{name}: #{desc} (CORE)" end)

    project_lines =
      loaded
      |> Enum.take(15)
      |> Enum.map(fn p -> "#{p.subsystem || p.title}: #{p.description}" end)

    core_lines ++ project_lines
  end

  # ── Private: Gap Detection ──────────────────────────────────────────

  defp reject_filled(gaps, loaded) do
    subsystem_names = Enum.map(loaded, fn p -> p.subsystem || p.title || "" end)

    Enum.reject(gaps, fn {_desc, markers} ->
      Enum.any?(markers, fn marker ->
        Enum.any?(subsystem_names, &String.contains?(&1, marker))
      end)
    end)
    |> Enum.map(fn {desc, _markers} -> desc end)
  end

  # ── Private: Dead Zones ─────────────────────────────────────────────

  defp auto_dead_zones(all) do
    failed_or_proposed = Enum.filter(all, &(&1.status in [:proposed, :failed]))
    loaded_titles = all |> Enum.filter(&(&1.status == :loaded)) |> MapSet.new(& &1.title)

    failed_or_proposed
    |> Enum.frequencies_by(&normalize_title/1)
    |> Enum.filter(fn {_title, count} -> count >= @dead_zone_threshold end)
    |> Enum.reject(fn {title, _count} -> MapSet.member?(loaded_titles, title) end)
    |> Enum.map(fn {title, _count} -> title end)
  end

  defp normalize_title(%{title: title}), do: title

  # ── Private: Rendering ──────────────────────────────────────────────

  defp render_lines(items) do
    Enum.map_join(items, "\n    ", &"- #{&1}")
  end
end
