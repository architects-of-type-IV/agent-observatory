defmodule IchorWeb.Components.MesPhaseRenderer do
  @moduledoc "Renders Phase hierarchy (sections, tasks, subtasks) as HTML for the reader sidebar."

  use Phoenix.Component

  @doc "Render a phase's full hierarchy as an HTML string."
  @spec render(map()) :: String.t()
  def render(phase) do
    sections = safe_list(phase, :sections)
    tasks = Enum.flat_map(sections, &safe_list(&1, :tasks))
    subtasks = Enum.flat_map(tasks, &safe_list(&1, :subtasks))

    assigns = %{
      goals: Map.get(phase, :goals, []),
      sections: sections,
      stats: %{sections: length(sections), tasks: length(tasks), subtasks: length(subtasks)}
    }

    assigns
    |> phase_detail()
    |> Phoenix.HTML.Safe.to_iodata()
    |> IO.iodata_to_binary()
  end

  defp phase_detail(assigns) do
    ~H"""
    <.stats_bar stats={@stats} />
    <.goals_list :if={@goals != []} goals={@goals} />
    <.section_card :for={section <- @sections} section={section} />
    """
  end

  attr :stats, :map, required: true

  defp stats_bar(assigns) do
    ~H"""
    <div class="flex gap-3 mb-4 p-2 rounded-md bg-zinc-800/50 border border-zinc-700/50">
      <.stat_pill label="Sections" count={@stats.sections} />
      <.stat_pill label="Tasks" count={@stats.tasks} />
      <.stat_pill label="Subtasks" count={@stats.subtasks} />
    </div>
    """
  end

  attr :label, :string, required: true
  attr :count, :integer, required: true

  defp stat_pill(assigns) do
    ~H"""
    <div class="text-center">
      <div class="text-base font-bold text-zinc-300 tabular-nums">{@count}</div>
      <div class="text-[7px] text-zinc-500 uppercase tracking-wider font-semibold">{@label}</div>
    </div>
    """
  end

  attr :goals, :list, required: true

  defp goals_list(assigns) do
    ~H"""
    <div class="mb-4">
      <div class="text-[8px] font-bold text-zinc-500 uppercase tracking-wider mb-1.5">Goals</div>
      <ul class="space-y-0.5 pl-4 list-disc">
        <li :for={goal <- @goals} class="text-[11px] text-zinc-400 leading-relaxed">{goal}</li>
      </ul>
    </div>
    """
  end

  attr :section, :map, required: true

  defp section_card(assigns) do
    tasks = safe_list(assigns.section, :tasks)
    assigns = assign(assigns, :tasks, tasks)

    ~H"""
    <div class="mb-4 p-3 rounded-md bg-zinc-900/60 border border-zinc-800/60">
      <div class="flex items-center gap-2 mb-2">
        <span class="text-[9px] font-bold text-success bg-success/10 px-1.5 py-0.5 rounded tabular-nums">
          S{@section.number}
        </span>
        <span class="text-xs font-semibold text-zinc-200">{@section.title}</span>
      </div>
      <p
        :if={Map.get(@section, :goal) not in [nil, ""]}
        class="text-[10px] text-zinc-500 italic mb-2 leading-relaxed"
      >
        {Map.get(@section, :goal)}
      </p>
      <.task_row :for={task <- @tasks} task={task} />
    </div>
    """
  end

  attr :task, :map, required: true

  defp task_row(assigns) do
    subtasks = safe_list(assigns.task, :subtasks)
    governed = safe_list(assigns.task, :governed_by)
    parent_uc = Map.get(assigns.task, :parent_uc)
    {dot_color, dot_title} = status_dot(assigns.task.status)

    assigns =
      assign(assigns,
        subtasks: subtasks,
        governed: governed,
        parent_uc: parent_uc,
        dot_color: dot_color,
        dot_title: dot_title
      )

    ~H"""
    <div class="mb-2">
      <div class="flex items-center gap-1.5">
        <span class={"w-1.5 h-1.5 rounded-full flex-shrink-0 #{@dot_color}"} title={@dot_title} />
        <span class="text-[11px] font-semibold text-zinc-300">{@task.number}. {@task.title}</span>
      </div>
      <div :if={@governed != [] or not is_nil(@parent_uc)} class="flex flex-wrap gap-1 mt-0.5 ml-3">
        <span
          :for={code <- @governed}
          class="text-[8px] px-1 py-0.5 rounded bg-brand/10 text-brand font-mono"
        >
          {code}
        </span>
        <span
          :if={not is_nil(@parent_uc)}
          class="text-[8px] px-1 py-0.5 rounded bg-interactive/10 text-interactive font-mono"
        >
          {@parent_uc}
        </span>
      </div>
      <div :if={@subtasks != []} class="mt-1 ml-3 border-l border-zinc-800 pl-2.5">
        <.subtask_row :for={st <- @subtasks} subtask={st} />
      </div>
    </div>
    """
  end

  attr :subtask, :map, required: true

  defp subtask_row(assigns) do
    blocked = safe_list(assigns.subtask, :blocked_by)
    {dot_color, _} = status_dot(assigns.subtask.status)
    assigns = assign(assigns, blocked: blocked, dot_color: dot_color)

    ~H"""
    <div class="py-0.5">
      <div class="flex items-center gap-1.5">
        <span class={"w-1 h-1 rounded-full flex-shrink-0 #{@dot_color}"} />
        <span class="text-[10px] text-zinc-400">{@subtask.number}. {@subtask.title}</span>
        <span :if={@blocked != []} class="text-[7px] text-zinc-600 font-mono ml-1">
          blocked: {Enum.map_join(@blocked, ", ", &String.slice(&1, 0, 8))}
        </span>
      </div>
      <div
        :if={Map.get(@subtask, :goal) not in [nil, ""]}
        class="text-[9px] text-zinc-600 ml-2.5 leading-snug"
      >
        {Map.get(@subtask, :goal)}
      </div>
    </div>
    """
  end

  defp status_dot(:completed), do: {"bg-success", "completed"}
  defp status_dot(:in_progress), do: {"bg-warning", "in progress"}
  defp status_dot(_), do: {"bg-zinc-700", "pending"}

  defp safe_list(nil, _key), do: []

  defp safe_list(node, key) do
    case Map.get(node, key, []) do
      list when is_list(list) -> list
      _ -> []
    end
  end
end
