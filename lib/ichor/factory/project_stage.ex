defmodule Ichor.Factory.ProjectStage do
  @moduledoc """
  Derives planning/build stage from a project's embedded artifacts and roadmap.
  """

  alias Ichor.Factory.Pipeline

  @type stage ::
          :ideation
          | :mode_a
          | :pre_gate_a
          | :mode_b
          | :pre_gate_b
          | :mode_c
          | :pre_gate_c
          | :ready_for_pipeline
          | :building
          | :compiled
          | :running

  @doc "Derive the pipeline stage from a loaded project. Returns stage atom and display label."
  @spec derive(map() | nil) :: {stage(), String.t()}
  def derive(nil), do: {:ideation, "Ideation"}

  def derive(project) do
    stage =
      case has_active_pipeline?(project) do
        true -> :building
        false -> classify(project)
      end

    {stage, label(stage)}
  end

  @doc "Compute station states for Mode A/B/C/Gate/Pipeline buttons."
  @spec station_states(stage()) :: %{
          a: :active | :completed | :future,
          b: :active | :completed | :future,
          c: :active | :completed | :future,
          gate: :active | :completed | :future,
          pipeline: :active | :completed | :future
        }
  def station_states(:ideation),
    do: %{a: :active, b: :future, c: :future, gate: :future, pipeline: :future}

  def station_states(:mode_a),
    do: %{a: :active, b: :future, c: :future, gate: :future, pipeline: :future}

  def station_states(:pre_gate_a),
    do: %{a: :completed, b: :future, c: :future, gate: :active, pipeline: :future}

  def station_states(:mode_b),
    do: %{a: :completed, b: :active, c: :future, gate: :future, pipeline: :future}

  def station_states(:pre_gate_b),
    do: %{a: :completed, b: :completed, c: :future, gate: :active, pipeline: :future}

  def station_states(:mode_c),
    do: %{a: :completed, b: :completed, c: :active, gate: :future, pipeline: :future}

  def station_states(:pre_gate_c),
    do: %{a: :completed, b: :completed, c: :completed, gate: :active, pipeline: :future}

  def station_states(:ready_for_pipeline),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, pipeline: :active}

  def station_states(:building),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, pipeline: :active}

  def station_states(:compiled),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, pipeline: :completed}

  def station_states(:running),
    do: %{a: :completed, b: :completed, c: :completed, gate: :completed, pipeline: :completed}

  @doc "Returns {text_css_class, bg_css_class} Tailwind classes for a pipeline stage."
  @spec stage_color(stage()) :: {String.t(), String.t()}
  def stage_color(:ideation), do: {"text-brand", "bg-brand/15"}
  def stage_color(:mode_a), do: {"text-brand", "bg-brand/15"}
  def stage_color(:pre_gate_a), do: {"text-brand", "bg-brand/15"}
  def stage_color(:mode_b), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:pre_gate_b), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:mode_c), do: {"text-interactive", "bg-interactive/15"}
  def stage_color(:pre_gate_c), do: {"text-warning", "bg-warning/15"}
  def stage_color(:ready_for_pipeline), do: {"text-warning", "bg-warning/15"}
  def stage_color(:building), do: {"text-warning", "bg-warning/15"}
  def stage_color(:compiled), do: {"text-success", "bg-success/15"}
  def stage_color(:running), do: {"text-success", "bg-success/15"}

  defp classify(project) do
    cond do
      roadmap_count(project, :phase) > 0 ->
        if gate_c_checkpoint?(artifacts(project, :checkpoint)),
          do: :ready_for_pipeline,
          else: :pre_gate_c

      artifact_count(project, :feature) > 0 or artifact_count(project, :use_case) > 0 ->
        if gate_b_checkpoint?(artifacts(project, :checkpoint)), do: :mode_c, else: :pre_gate_b

      artifact_count(project, :adr) > 0 ->
        if gate_a_checkpoint?(artifacts(project, :checkpoint)), do: :mode_b, else: :pre_gate_a

      true ->
        :mode_a
    end
  end

  defp gate_a_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_a)
  defp gate_b_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_b)
  defp gate_c_checkpoint?(checkpoints), do: has_checkpoint_mode?(checkpoints, :gate_c)

  defp has_checkpoint_mode?(checkpoints, _mode) when not is_list(checkpoints), do: false
  defp has_checkpoint_mode?([], _mode), do: false

  defp has_checkpoint_mode?(checkpoints, mode) do
    Enum.any?(checkpoints, fn cp -> cp.mode == mode or cp.mode == to_string(mode) end)
  end

  defp has_active_pipeline?(nil), do: false

  defp has_active_pipeline?(%{id: project_id}) when is_binary(project_id) do
    Pipeline.by_project!(project_id) != []
  end

  defp has_active_pipeline?(_), do: false

  defp artifacts(node, kind), do: Enum.filter(Map.get(node, :artifacts, []), &(&1.kind == kind))

  defp artifact_count(node, kind),
    do: Enum.count(Map.get(node, :artifacts, []), &(&1.kind == kind))

  defp roadmap_count(node, kind),
    do: Enum.count(Map.get(node, :roadmap_items, []), &(&1.kind == kind))

  @labels %{
    ideation: "Ideation",
    mode_a: "Mode A",
    pre_gate_a: "Pre-Gate A",
    mode_b: "Mode B",
    pre_gate_b: "Pre-Gate B",
    mode_c: "Mode C",
    pre_gate_c: "Pre-Gate C",
    ready_for_pipeline: "Ready for Build",
    building: "Building",
    compiled: "Compiled",
    running: "Running"
  }

  defp label(stage), do: Map.get(@labels, stage, to_string(stage))
end
