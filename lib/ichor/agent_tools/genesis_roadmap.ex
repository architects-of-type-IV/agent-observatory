defmodule Ichor.AgentTools.GenesisRoadmap do
  @moduledoc """
  MCP tools for Mode C roadmap hierarchy: Phase, Section, Task, Subtask.
  """
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Genesis.{Phase, Section, Task, Subtask}

  actions do
    action :create_phase, :map do
      description("Create a roadmap Phase for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:number, :integer, allow_nil?: false, description: "Phase number (1-based)")
      argument(:title, :string, allow_nil?: false, description: "Phase title")
      argument(:goals, :string, allow_nil?: true, description: "Comma-separated goals")

      argument(:governed_by, :string,
        allow_nil?: true,
        description: "Comma-separated FRD/ADR codes"
      )

      run(fn input, _context ->
        args = input.arguments

        Phase.create(%{
          number: args.number,
          title: args.title,
          goals: split_csv(args[:goals]),
          governed_by: split_csv(args[:governed_by]),
          node_id: args.node_id
        })
        |> to_map([:number, :title, :status, :goals, :governed_by, :node_id])
      end)
    end

    action :create_section, :map do
      description("Create a Section within a Phase.")

      argument(:phase_id, :string, allow_nil?: false, description: "Phase UUID")
      argument(:number, :integer, allow_nil?: false, description: "Section number")
      argument(:title, :string, allow_nil?: false, description: "Section title")
      argument(:goal, :string, allow_nil?: true, description: "Section goal")

      run(fn input, _context ->
        args = input.arguments

        Section.create(%{
          number: args.number,
          title: args.title,
          goal: args[:goal],
          phase_id: args.phase_id
        })
        |> to_map([:number, :title, :goal, :phase_id])
      end)
    end

    action :create_task, :map do
      description("Create a Task within a Section.")

      argument(:section_id, :string, allow_nil?: false, description: "Section UUID")
      argument(:number, :integer, allow_nil?: false, description: "Task number")
      argument(:title, :string, allow_nil?: false, description: "Task title")

      argument(:governed_by, :string,
        allow_nil?: true,
        description: "Comma-separated FRD/ADR codes"
      )

      argument(:parent_uc, :string, allow_nil?: true, description: "UseCase code this implements")

      run(fn input, _context ->
        args = input.arguments

        Task.create(%{
          number: args.number,
          title: args.title,
          governed_by: split_csv(args[:governed_by]),
          parent_uc: args[:parent_uc],
          section_id: args.section_id
        })
        |> to_map([:number, :title, :status, :governed_by, :parent_uc, :section_id])
      end)
    end

    action :create_subtask, :map do
      description("Create a Subtask within a Task. Subtasks are DAG-ready work units.")

      argument(:task_id, :string, allow_nil?: false, description: "Task UUID")
      argument(:number, :integer, allow_nil?: false, description: "Subtask number")
      argument(:title, :string, allow_nil?: false, description: "Subtask title")
      argument(:goal, :string, allow_nil?: true, description: "What success looks like")

      argument(:allowed_files, :string,
        allow_nil?: true,
        description: "Comma-separated file paths"
      )

      argument(:blocked_by, :string, allow_nil?: true, description: "Comma-separated subtask IDs")

      argument(:steps, :string,
        allow_nil?: true,
        description: "Comma-separated implementation steps"
      )

      argument(:done_when, :string, allow_nil?: true, description: "Verification command")

      run(fn input, _context ->
        args = input.arguments

        Subtask.create(%{
          number: args.number,
          title: args.title,
          goal: args[:goal],
          allowed_files: split_csv(args[:allowed_files]),
          blocked_by: split_csv(args[:blocked_by]),
          steps: split_csv(args[:steps]),
          done_when: args[:done_when],
          task_id: args.task_id
        })
        |> to_map([
          :number,
          :title,
          :status,
          :goal,
          :allowed_files,
          :blocked_by,
          :steps,
          :done_when,
          :task_id
        ])
      end)
    end

    action :list_phases, {:array, :map} do
      description(
        "List all Phases for a Genesis Node with nested sections, tasks, and subtask counts."
      )

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        case Phase.by_node(input.arguments.node_id) do
          {:ok, phases} ->
            loaded =
              Enum.map(phases, fn phase ->
                {:ok, p} = Ash.load(phase, sections: [tasks: [:subtasks]])
                summarize_phase(p)
              end)

            {:ok, loaded}

          error ->
            error
        end
      end)
    end
  end

  defp summarize_phase(p) do
    %{
      "id" => p.id,
      "number" => p.number,
      "title" => p.title,
      "status" => to_string(p.status),
      "sections" => Enum.map(p.sections, &summarize_section/1)
    }
  end

  defp summarize_section(s) do
    %{
      "id" => s.id,
      "number" => s.number,
      "title" => s.title,
      "tasks" => Enum.map(s.tasks, &summarize_task/1)
    }
  end

  defp summarize_task(t) do
    %{
      "id" => t.id,
      "number" => t.number,
      "title" => t.title,
      "status" => to_string(t.status),
      "subtasks" => length(t.subtasks)
    }
  end

  defp to_map({:ok, record}, fields) do
    Ichor.Signals.emit(:genesis_artifact_created, %{
      id: record.id,
      node_id:
        Map.get(record, :node_id) || Map.get(record, :phase_id) || Map.get(record, :section_id) ||
          Map.get(record, :task_id),
      type: record.__struct__ |> Module.split() |> List.last() |> String.downcase()
    })

    {:ok,
     Map.take(record, [:id | fields])
     |> Map.new(fn {k, v} -> {to_string(k), stringify(v)} end)
     |> Map.reject(fn {_k, v} -> is_nil(v) end)}
  end

  defp to_map(error, _fields), do: error

  defp stringify(val) when is_atom(val), do: to_string(val)
  defp stringify(val) when is_list(val), do: Enum.join(val, ", ")
  defp stringify(val), do: val

  defp split_csv(nil), do: []

  defp split_csv(str),
    do: str |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
end
