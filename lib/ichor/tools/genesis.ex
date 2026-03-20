defmodule Ichor.Tools.Genesis do
  @moduledoc """
  MCP tools for the full Genesis pipeline: nodes, artifacts (ADRs, Features, UseCases),
  gate checkpoints, design conversations, and Mode C roadmap hierarchy.
  """
  use Ash.Resource, domain: Ichor.Tools

  alias Ichor.Projects.{
    Adr,
    Checkpoint,
    Conversation,
    Feature,
    Phase,
    RoadmapTask,
    Section,
    Subtask,
    UseCase
  }

  alias Ichor.Projects.Node

  @node_status_map %{
    "discover" => :discover,
    "define" => :define,
    "build" => :build,
    "complete" => :complete
  }

  @valid_adr_statuses %{
    "pending" => :pending,
    "proposed" => :proposed,
    "accepted" => :accepted,
    "rejected" => :rejected
  }

  @valid_modes %{
    "discover" => :discover,
    "define" => :define,
    "build" => :build,
    "gate_a" => :gate_a,
    "gate_b" => :gate_b,
    "gate_c" => :gate_c
  }

  @artifact_fields ~w(id code title status content mode summary feature_code adr_codes node_id)a

  actions do
    # ── Node lifecycle ──────────────────────────────────────────────────────────

    action :create_genesis_node, :map do
      description("Create a new Genesis Node from a subsystem proposal. Starts in discover mode.")

      argument :title, :string do
        allow_nil?(false)
        description("Node title (subsystem name)")
      end

      argument :description, :string do
        allow_nil?(false)
        description("What this subsystem does")
      end

      argument :brief, :string do
        allow_nil?(false)
        default("")
        description("Original MES brief content. Empty if not from MES.")
      end

      argument :mes_project_id, :string do
        allow_nil?(false)
        default("")
        description("MES Project UUID that spawned this node. Empty if standalone.")
      end

      run(fn input, _context ->
        args = input.arguments

        with {:ok, node} <-
               Node.create(Map.take(args, [:title, :description, :brief, :mes_project_id])) do
          {:ok, summarize_node(node)}
        end
      end)
    end

    action :advance_node, :map do
      description("Advance a Genesis Node to the next pipeline stage.")

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      argument :status, :string do
        allow_nil?(false)
        description("Target status: discover, define, build, or complete")
      end

      run(fn input, _context ->
        with {:ok, node} <- Node.get(input.arguments.node_id),
             {:ok, status} <- Map.fetch(@node_status_map, input.arguments.status),
             {:ok, updated} <- Node.advance(node, status) do
          {:ok, summarize_node(updated)}
        else
          :error -> {:error, "invalid status: #{input.arguments.status}"}
          err -> err
        end
      end)
    end

    action :list_genesis_nodes, {:array, :map} do
      description("List all Genesis Nodes with their current pipeline status.")

      run(fn _input, _context ->
        case Node.list_all() do
          {:ok, nodes} -> {:ok, Enum.map(nodes, &summarize_node/1)}
          error -> error
        end
      end)
    end

    action :get_genesis_node, :map do
      description("Get a Genesis Node with artifact counts.")

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      run(fn input, _context ->
        with {:ok, loaded} <-
               Node.get(input.arguments.node_id,
                 load: [:adrs, :features, :use_cases, :checkpoints, :conversations, :phases]
               ) do
          {:ok, detail_node(loaded)}
        end
      end)
    end

    action :gate_check, :map do
      description(
        "Run a readiness check for advancing to the next pipeline stage. Returns artifact counts and missing items."
      )

      argument :node_id, :string do
        allow_nil?(false)
        description("Genesis Node UUID")
      end

      run(fn input, _context ->
        with {:ok, loaded} <-
               Node.get(input.arguments.node_id,
                 load: [:adrs, :features, :use_cases, :checkpoints, :phases]
               ) do
          {:ok, gate_report(loaded)}
        end
      end)
    end

    # ── ADRs ────────────────────────────────────────────────────────────────────

    action :create_adr, :map do
      description("Create an Architecture Decision Record for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "ADR code, e.g. ADR-001")
      argument(:title, :string, allow_nil?: false, description: "ADR title")
      argument(:content, :string, allow_nil?: false, default: "", description: "ADR body text")

      argument(:status, :string,
        allow_nil?: false,
        default: "pending",
        description: "pending, proposed, accepted, or rejected"
      )

      run(fn input, _context ->
        args = input.arguments
        status = parse_enum(args.status, :pending, @valid_adr_statuses)

        Adr.create(%{
          code: args.code,
          title: args.title,
          content: if(args.content == "", do: nil, else: args.content),
          status: status,
          node_id: args.node_id
        })
        |> to_map(@artifact_fields)
      end)
    end

    action :update_adr, :map do
      description("Update an existing ADR's status or content.")

      argument(:adr_id, :string, allow_nil?: false, description: "ADR UUID")
      argument(:status, :string, allow_nil?: false, default: "", description: "New status")

      argument(:content, :string,
        allow_nil?: false,
        default: "",
        description: "Updated body text"
      )

      run(fn input, _context ->
        with {:ok, adr} <- Adr.get(input.arguments.adr_id) do
          status_str = if input.arguments.status == "", do: nil, else: input.arguments.status
          content_val = if input.arguments.content == "", do: nil, else: input.arguments.content

          attrs =
            %{}
            |> put_if(:status, parse_enum(status_str, nil, @valid_adr_statuses))
            |> put_if(:content, content_val)

          Adr.update(adr, attrs) |> to_map(@artifact_fields)
        end
      end)
    end

    action :list_adrs, {:array, :map} do
      description("List all ADRs for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, adrs} <- Adr.by_node(input.arguments.node_id) do
          {:ok, Enum.map(adrs, &summarize(&1, [:code, :title, :status]))}
        end
      end)
    end

    # ── Features ────────────────────────────────────────────────────────────────

    action :create_feature, :map do
      description("Create a Feature Requirements Document for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "Feature code, e.g. FRD-001")
      argument(:title, :string, allow_nil?: false, description: "Feature title")

      argument(:content, :string,
        allow_nil?: false,
        default: "",
        description: "FRD body with inline FRs"
      )

      argument(:adr_codes, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated ADR codes"
      )

      run(fn input, _context ->
        args = input.arguments

        Feature.create(%{
          code: args.code,
          title: args.title,
          content: if(args.content == "", do: nil, else: args.content),
          adr_codes: split_csv(args.adr_codes),
          node_id: args.node_id
        })
        |> to_map(@artifact_fields)
      end)
    end

    action :list_features, {:array, :map} do
      description("List all Features for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, features} <- Feature.by_node(input.arguments.node_id) do
          {:ok, Enum.map(features, &summarize(&1, [:code, :title, :adr_codes]))}
        end
      end)
    end

    # ── Use Cases ───────────────────────────────────────────────────────────────

    action :create_use_case, :map do
      description("Create a Use Case with Gherkin scenarios for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:code, :string, allow_nil?: false, description: "UC code, e.g. UC-0001")
      argument(:title, :string, allow_nil?: false, description: "Use case title")

      argument(:content, :string,
        allow_nil?: false,
        default: "",
        description: "UC body with Gherkin scenarios"
      )

      argument(:feature_code, :string,
        allow_nil?: false,
        default: "",
        description: "Feature code this UC validates"
      )

      run(fn input, _context ->
        args = input.arguments

        UseCase.create(%{
          code: args.code,
          title: args.title,
          content: if(args.content == "", do: nil, else: args.content),
          feature_code: if(args.feature_code == "", do: nil, else: args.feature_code),
          node_id: args.node_id
        })
        |> to_map(@artifact_fields)
      end)
    end

    action :list_use_cases, {:array, :map} do
      description("List all Use Cases for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        with {:ok, ucs} <- UseCase.by_node(input.arguments.node_id) do
          {:ok, Enum.map(ucs, &summarize(&1, [:code, :title, :feature_code]))}
        end
      end)
    end

    # ── Gate checkpoints ────────────────────────────────────────────────────────

    action :create_checkpoint, :map do
      description("Create a gate checkpoint recording readiness assessment.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:title, :string, allow_nil?: false, description: "Checkpoint title")
      argument(:mode, :string, allow_nil?: false, description: "Mode: discover, define, or build")

      argument(:content, :string,
        allow_nil?: false,
        default: "",
        description: "Gate check report"
      )

      argument(:summary, :string, allow_nil?: false, default: "", description: "One-line verdict")

      run(fn input, _context ->
        args = input.arguments

        case Map.fetch(@valid_modes, args.mode) do
          {:ok, mode} ->
            Checkpoint.create(%{
              title: args.title,
              mode: mode,
              content: if(args.content == "", do: nil, else: args.content),
              summary: if(args.summary == "", do: nil, else: args.summary),
              node_id: args.node_id
            })
            |> to_map([:title, :mode, :content, :summary, :node_id])

          :error ->
            {:error, "unknown mode: #{args.mode}"}
        end
      end)
    end

    # ── Conversations ───────────────────────────────────────────────────────────

    action :create_conversation, :map do
      description("Log a design conversation from a mode session.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:title, :string, allow_nil?: false, description: "Conversation title")
      argument(:mode, :string, allow_nil?: false, description: "Mode: discover, define, or build")

      argument(:content, :string,
        allow_nil?: false,
        default: "",
        description: "Transcript or summary"
      )

      run(fn input, _context ->
        args = input.arguments

        case Map.fetch(@valid_modes, args.mode) do
          {:ok, mode} ->
            Conversation.create(%{
              title: args.title,
              mode: mode,
              content: if(args.content == "", do: nil, else: args.content),
              node_id: args.node_id
            })
            |> to_map([:title, :mode, :content, :summary, :node_id])

          :error ->
            {:error, "unknown mode: #{args.mode}"}
        end
      end)
    end

    action :list_conversations, {:array, :map} do
      description("List all conversations for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")

      run(fn input, _context ->
        case Conversation.by_node(input.arguments.node_id) do
          {:ok, convs} -> {:ok, Enum.map(convs, &summarize(&1, [:title, :mode]))}
          error -> error
        end
      end)
    end

    # ── Mode C roadmap ──────────────────────────────────────────────────────────

    action :create_phase, :map do
      description("Create a roadmap Phase for a Genesis Node.")

      argument(:node_id, :string, allow_nil?: false, description: "Genesis Node UUID")
      argument(:number, :integer, allow_nil?: false, description: "Phase number (1-based)")
      argument(:title, :string, allow_nil?: false, description: "Phase title")

      argument(:goals, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated goals"
      )

      argument(:governed_by, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated FRD/ADR codes"
      )

      run(fn input, _context ->
        args = input.arguments

        Phase.create(%{
          number: args.number,
          title: args.title,
          goals: split_csv(args.goals),
          governed_by: split_csv(args.governed_by),
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
      argument(:goal, :string, allow_nil?: false, default: "", description: "Section goal")

      run(fn input, _context ->
        args = input.arguments

        Section.create(%{
          number: args.number,
          title: args.title,
          goal: if(args.goal == "", do: nil, else: args.goal),
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
        allow_nil?: false,
        default: "",
        description: "Comma-separated FRD/ADR codes"
      )

      argument(:parent_uc, :string,
        allow_nil?: false,
        default: "",
        description: "UseCase code this implements"
      )

      run(fn input, _context ->
        args = input.arguments

        RoadmapTask.create(%{
          number: args.number,
          title: args.title,
          governed_by: split_csv(args.governed_by),
          parent_uc: if(args.parent_uc == "", do: nil, else: args.parent_uc),
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

      argument(:goal, :string,
        allow_nil?: false,
        default: "",
        description: "What success looks like"
      )

      argument(:allowed_files, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated file paths"
      )

      argument(:blocked_by, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated subtask IDs"
      )

      argument(:steps, :string,
        allow_nil?: false,
        default: "",
        description: "Comma-separated implementation steps"
      )

      argument(:done_when, :string,
        allow_nil?: false,
        default: "",
        description: "Verification command"
      )

      run(fn input, _context ->
        args = input.arguments

        Subtask.create(%{
          number: args.number,
          title: args.title,
          goal: if(args.goal == "", do: nil, else: args.goal),
          allowed_files: split_csv(args.allowed_files),
          blocked_by: split_csv(args.blocked_by),
          steps: split_csv(args.steps),
          done_when: if(args.done_when == "", do: nil, else: args.done_when),
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
        with {:ok, phases} <- Phase.by_node(input.arguments.node_id) do
          summaries =
            Enum.map(phases, fn phase ->
              {:ok, p} = Phase.with_hierarchy(phase.id)
              summarize_phase(p)
            end)

          {:ok, summaries}
        end
      end)
    end
  end

  # ── Node helpers ───────────────────────────────────────────────────────────

  defp summarize_node(node) do
    %{
      "id" => node.id,
      "title" => node.title,
      "status" => to_string(node.status),
      "description" => node.description
    }
  end

  defp detail_node(node) do
    %{
      "id" => node.id,
      "title" => node.title,
      "status" => to_string(node.status),
      "description" => node.description,
      "adrs" => length(node.adrs),
      "features" => length(node.features),
      "use_cases" => length(node.use_cases),
      "checkpoints" => length(node.checkpoints),
      "conversations" => length(node.conversations),
      "phases" => length(node.phases)
    }
  end

  defp gate_report(node) do
    adrs = length(node.adrs)
    accepted_adrs = Enum.count(node.adrs, &(&1.status == :accepted))
    features = length(node.features)
    use_cases = length(node.use_cases)
    phases = length(node.phases)

    %{
      "node_id" => node.id,
      "current_status" => to_string(node.status),
      "adrs" => adrs,
      "accepted_adrs" => accepted_adrs,
      "features" => features,
      "use_cases" => use_cases,
      "checkpoints" => length(node.checkpoints),
      "phases" => phases,
      "ready_for_define" => adrs > 0 and accepted_adrs > 0,
      "ready_for_build" => features > 0 and use_cases > 0,
      "ready_for_complete" => phases > 0
    }
  end

  # ── Roadmap helpers ─────────────────────────────────────────────────────────

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

  # ── Formatter helpers (inlined from GenesisFormatter) ──────────────────────

  defp to_map({:ok, record}, fields) do
    {:ok,
     record
     |> Map.take([:id | fields])
     |> Enum.map(fn {key, value} -> {to_string(key), stringify(value)} end)
     |> Enum.reject(fn {_key, value} -> is_nil(value) end)
     |> Map.new()}
  end

  defp to_map(error, _fields), do: error

  defp summarize(record, fields) do
    Map.new([:id | fields], fn field ->
      {to_string(field), stringify(Map.get(record, field))}
    end)
  end

  defp stringify(value) when is_atom(value), do: to_string(value)
  defp stringify(value) when is_list(value), do: Enum.join(value, ", ")
  defp stringify(value), do: value

  defp split_csv(nil), do: []

  defp split_csv(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  defp parse_enum(nil, default, _mapping), do: default
  defp parse_enum(value, _default, _mapping) when is_atom(value), do: value

  defp parse_enum(value, default, mapping) when is_binary(value),
    do: Map.get(mapping, value, default)

  defp put_if(map, _key, nil), do: map
  defp put_if(map, key, value), do: Map.put(map, key, value)
end
