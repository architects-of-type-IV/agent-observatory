defmodule Ichor.AgentTools.GenesisRoadmap do
  @moduledoc "MCP tools for Mode C roadmap hierarchy: Phase, Section, Task, Subtask."
  use Ash.Resource, domain: Ichor.AgentTools

  alias Ichor.Projects
  alias Ichor.Tools.GenesisFormatter

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

        Projects.create_phase(%{
          number: args.number,
          title: args.title,
          goals: GenesisFormatter.split_csv(args[:goals]),
          governed_by: GenesisFormatter.split_csv(args[:governed_by]),
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

        Projects.create_section(%{
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

        Projects.create_task(%{
          number: args.number,
          title: args.title,
          governed_by: GenesisFormatter.split_csv(args[:governed_by]),
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

        Projects.create_subtask(%{
          number: args.number,
          title: args.title,
          goal: args[:goal],
          allowed_files: GenesisFormatter.split_csv(args[:allowed_files]),
          blocked_by: GenesisFormatter.split_csv(args[:blocked_by]),
          steps: GenesisFormatter.split_csv(args[:steps]),
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
        with {:ok, phases} <- Projects.phases_by_node(input.arguments.node_id) do
          summaries =
            Enum.map(phases, fn phase ->
              {:ok, p} = Ash.load(phase, sections: [tasks: [:subtasks]])
              summarize_phase(p)
            end)

          {:ok, summaries}
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

  defp to_map(result, fields), do: GenesisFormatter.to_map(result, fields)
end
