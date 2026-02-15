defmodule ObservatoryWeb.Components.TasksComponents do
  @moduledoc """
  Tasks/Kanban board view component for the Observatory dashboard.
  """

  use Phoenix.Component
  import ObservatoryWeb.ObservatoryComponents

  attr :status, :string, required: true
  attr :title, :string, required: true
  attr :tasks, :list, required: true
  attr :team_members, :list, default: []
  attr :team_name, :string, default: nil
  attr :dot_class, :string, default: "bg-zinc-500"
  attr :title_class, :string, default: "text-zinc-400"
  attr :card_border, :string, default: "border-zinc-800 hover:border-zinc-700"
  attr :owner_class, :string, default: "text-zinc-500"
  attr :subject_class, :string, default: "text-zinc-300"
  attr :show_active_form, :boolean, default: false
  attr :show_blocked_by, :boolean, default: false
  attr :animate_dot, :boolean, default: false

  def task_column(assigns) do
    ~H"""
    <div>
      <div class="flex items-center gap-2 mb-3 px-1">
        <span class={"w-2 h-2 rounded-full #{@dot_class} #{if @animate_dot, do: "animate-pulse", else: ""}"}>
        </span>
        <h3 class={"text-xs font-semibold #{@title_class} uppercase tracking-wider"}>{@title}</h3>
        <span class="text-xs text-zinc-600">
          ({length(Enum.filter(@tasks, fn t -> t[:status] == @status end))})
        </span>
      </div>
      <div class="space-y-2">
        <div
          :for={task <- Enum.filter(@tasks, fn t -> t[:status] == @status end)}
          class={"p-3 rounded-lg bg-zinc-900 border #{@card_border} transition"}
        >
          <div class="flex items-center justify-between mb-2">
            <span class="text-xs font-mono text-zinc-600">#{task[:id]}</span>
            <button
              :if={@team_name}
              phx-click="delete_task"
              phx-value-team={@team_name}
              phx-value-task_id={task[:id]}
              data-confirm={"Delete task ##{task[:id]}?"}
              class="text-xs text-red-400/50 hover:text-red-400 transition"
            >
              x
            </button>
          </div>
          <div class="mb-2 cursor-pointer group" phx-click="select_task" phx-value-id={task[:id]}>
            <p class={"text-sm #{@subject_class} group-hover:text-zinc-200 transition"}>
              {task[:subject]}
            </p>
          </div>
          <p :if={@show_active_form && task[:active_form]} class="text-xs text-blue-400/60 mb-2">
            {task[:active_form]}
          </p>
          <div :if={@team_name} class="mb-2">
            <label class="text-[10px] text-zinc-600 uppercase tracking-wider mb-0.5 block">
              Status
            </label>
            <select
              phx-change="update_task_status"
              phx-value-team={@team_name}
              phx-value-task_id={task[:id]}
              name="status"
              class="w-full px-2 py-1 text-xs bg-zinc-800 border border-zinc-700 rounded text-zinc-200 focus:outline-none focus:border-blue-500"
            >
              <option value="pending" selected={task[:status] == "pending"}>Pending</option>
              <option value="in_progress" selected={task[:status] == "in_progress"}>
                In Progress
              </option>
              <option value="completed" selected={task[:status] == "completed"}>Completed</option>
            </select>
          </div>
          <div :if={@team_name && @team_members != []} class="mb-2">
            <label class="text-[10px] text-zinc-600 uppercase tracking-wider mb-0.5 block">
              Owner
            </label>
            <select
              phx-change="reassign_task"
              phx-value-team={@team_name}
              phx-value-task_id={task[:id]}
              name="owner"
              class="w-full px-2 py-1 text-xs bg-zinc-800 border border-zinc-700 rounded text-zinc-200 focus:outline-none focus:border-blue-500"
            >
              <option value="" selected={!task[:owner] || task[:owner] == ""}>Unassigned</option>
              <option
                :for={member <- @team_members}
                value={member[:agent_id] || member[:name]}
                selected={task[:owner] == (member[:agent_id] || member[:name])}
              >
                {member[:name] || member[:agent_id]}
              </option>
            </select>
          </div>
          <div :if={@team_name && @team_members == [] && task[:owner]} class="mb-2">
            <span class="text-[10px] text-zinc-600 uppercase tracking-wider">Owner:</span>
            <span class="text-xs text-zinc-400 ml-1">{task[:owner]}</span>
          </div>
          <div :if={@show_blocked_by && task[:blocked_by] && task[:blocked_by] != []} class="mt-1.5">
            <span class="text-xs text-amber-500/70">
              blocked by #{Enum.join(task[:blocked_by], ", #")}
            </span>
          </div>
        </div>
      </div>
    </div>
    """
  end

  attr :active_tasks, :list, required: true
  attr :selected_team, :any, default: nil
  attr :sel_team, :any, default: nil

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
          team_members={if @sel_team, do: @sel_team.members, else: []}
          team_name={@selected_team}
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
          team_members={if @sel_team, do: @sel_team.members, else: []}
          team_name={@selected_team}
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
          team_members={if @sel_team, do: @sel_team.members, else: []}
          team_name={@selected_team}
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
