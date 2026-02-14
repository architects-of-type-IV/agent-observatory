defmodule ObservatoryWeb.Components.TasksComponents do
  @moduledoc """
  Tasks/Kanban board view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents

  attr :active_tasks, :list, required: true
  attr :selected_team, :any, default: nil

  def tasks_view(assigns) do
    ~H"""
    <div class="p-4">
      <div class="flex justify-between items-center mb-4">
        <h2 class="text-sm font-semibold text-zinc-400">Task Board</h2>
        <button
          :if={@selected_team}
          phx-click="toggle_create_task_modal"
          class="px-3 py-1 text-xs rounded-md bg-blue-600 hover:bg-blue-500 text-white transition"
        >
          + New Task
        </button>
      </div>

      <.empty_state
        :if={@active_tasks == []}
        title="No tasks tracked yet"
        description="Tasks will appear when agents use TaskCreate or TaskUpdate tools"
      />

      <div :if={@active_tasks != []} class="grid grid-cols-3 gap-4 min-w-0">
        <.task_column
          status="pending"
          title="Pending"
          tasks={@active_tasks}
          dot_class="bg-zinc-500"
          title_class="text-zinc-400"
          card_border="border-zinc-800 hover:border-zinc-700"
          owner_class="text-zinc-500"
          show_blocked_by={true}
        />

        <.task_column
          status="in_progress"
          title="In Progress"
          tasks={@active_tasks}
          dot_class="bg-blue-500"
          title_class="text-blue-400"
          card_border="border-blue-500/20 hover:border-blue-500/40"
          owner_class="text-blue-400"
          show_active_form={true}
          animate_dot={true}
        />

        <.task_column
          status="completed"
          title="Completed"
          tasks={@active_tasks}
          dot_class="bg-emerald-500"
          title_class="text-emerald-400"
          card_border="border-emerald-500/15 hover:border-emerald-500/30"
          owner_class="text-emerald-400/70"
          subject_class="text-zinc-500 line-through"
        />
      </div>
    </div>
    """
  end
end
