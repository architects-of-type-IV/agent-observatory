defmodule Ichor.Genesis.PipelineStage do
  @moduledoc """
  Derives pipeline stage from a Genesis Node's loaded associations.
  Queries Ichor.Dag.Run for :building stage detection (cross-domain read).
  """

  @type stage ::
          :ideation
          | :mode_a
          | :pre_gate_a
          | :mode_b
          | :pre_gate_b
          | :mode_c
          | :pre_gate_c
          | :ready_for_dag
          | :building
          | :compiled
          | :running

  @doc "Derive the pipeline stage from a loaded genesis node. Returns stage atom and display label."
  @spec derive(map() | nil) :: {stage(), String.t()}
  def derive(nil), do: {:ideation, "Ideation"}

  def derive(node) do
    stage =
      case has_active_dag_run?(node) do
        true -> :building
        false -> classify(node)
      end

    {stage, label(stage)}
  end

  @doc "Compute station states for Mode A/B/C/Gate/DAG buttons."
  @spec station_states(stage()) :: %{
          a: :active | :completed | :future,
          b: :active | :completed | :future,
          c: :active | :completed | :future,
          gate: :active | :completed | :future,
          dag: :active | :completed | :future
        }
  def station_states(:ideation),
    do: %{a: :active, b: :future, c: :future, gate: :future, dag: :future}

  def station_states(:mode_a),
    do: %{a: :active, b: :future, c: :future, gate: :future, dag: :future}

  def station_states(:pre_gate_a),
    do: %{a: :completed, b: :future, c: :future, gate: :active, dag: :future}

  def station_states(:mode_b),
    do: %{a: :completed, b: :active, c: :future, gate: :future, dag: :future}

  def station_states(:pre_gate_b),
    do: %{a: :completed, b: :completed, c: :future, gate: :active, dag: :future}

  def station_states(:mode_c),
    do: %{a: :completed, b: :completed, c: :active, gate: :future, dag: :future}

  def station_states(:pre_gate_c),
    do: %{a: :completed, b: :completed, c: :completed, gate: :active, dag: :future}

  def station_states(:ready_for_dag),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, dag: :active}

  def station_states(:building),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, dag: :active}

  def station_states(:compiled),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, dag: :completed}

  def station_states(:running),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, dag: :completed}

  @doc "Returns {text_css_class, bg_css_class} Tailwind classes for a pipeline stage."
  @spec stage_color(stage()) :: {String.t(), String.t()}
  def stage_color(:ideation), do: {"text-brand", "bg-brand/15"}
  def stage_color(:mode_a), do: {"text-brand", "bg-brand/15"}
  def stage_color(:pre_gate_a), do: {"text-brand", "bg-brand/15"}
  def stage_color(:mode_b), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:pre_gate_b), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:mode_c), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:pre_gate_c), do: {"text-warning", "bg-warning/15"}
  def stage_color(:ready_for_dag), do: {"text-warning", "bg-warning/15"}
  def stage_color(:building), do: {"text-warning", "bg-warning/15"}
  def stage_color(:compiled), do: {"text-success", "bg-success/15"}
  def stage_color(:running), do: {"text-success", "bg-success/15"}

  # ── Private ─────────────────────────────────────────────────────────

  defp classify(%{phases: phases} = node) when is_list(phases) and phases != [] do
    case gate_c_checkpoint?(node.checkpoints) do
      true -> :ready_for_dag
      false -> :pre_gate_c
    end
  end

  defp classify(%{features: features, use_cases: use_cases} = node)
       when (is_list(features) and features != []) or
              (is_list(use_cases) and use_cases != []) do
    case gate_b_checkpoint?(node.checkpoints) do
      true -> :mode_c
      false -> :pre_gate_b
    end
  end

  defp classify(%{adrs: adrs} = node) when is_list(adrs) and adrs != [] do
    case gate_a_checkpoint?(node.checkpoints) do
      true -> :mode_b
      false -> :pre_gate_a
    end
  end

  defp classify(_node), do: :mode_a

  defp gate_a_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_a)
  defp gate_b_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_b)
  defp gate_c_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_c)

  defp has_checkpoint_mode?(checkpoints, _mode) when not is_list(checkpoints), do: false
  defp has_checkpoint_mode?([], _mode), do: false

  defp has_checkpoint_mode?(checkpoints, mode) do
    Enum.any?(checkpoints, fn cp -> cp.mode == mode or cp.mode == to_string(mode) end)
  end

  defp has_active_dag_run?(nil), do: false

  defp has_active_dag_run?(%{id: node_id}) when is_binary(node_id) do
    case Ichor.Dag.Run.by_node(node_id) do
      {:ok, [_ | _]} -> true
      _ -> false
    end
  end

  defp has_active_dag_run?(_), do: false

  @labels %{
    ideation: "Ideation",
    mode_a: "Mode A",
    pre_gate_a: "Pre-Gate A",
    mode_b: "Mode B",
    pre_gate_b: "Pre-Gate B",
    mode_c: "Mode C",
    pre_gate_c: "Pre-Gate C",
    ready_for_dag: "Ready for DAG",
    building: "Building",
    compiled: "Compiled",
    running: "Running"
  }

  defp label(stage), do: Map.get(@labels, stage, to_string(stage))
end
