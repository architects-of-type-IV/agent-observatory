defmodule AgentPromptDag do
  @moduledoc """
  Erlang `:digraph` representation of the AGENT_PROMPT.md decision framework.

  Source: `SPECS/dag/AGENT_PROMPT.md`
  YAML companion: `SPECS/dag/agent_prompt_dag.yml`
  DOT companion:  `SPECS/dag/agent_prompt_dag.dot`

  ## Usage

      # Build the graph
      g = AgentPromptDag.build()

      # Topological sort (all 24 nodes in reasoning order)
      AgentPromptDag.topsort(g)

      # All nodes reachable from :START
      AgentPromptDag.reachable(g, :START)

      # All paths from :START to a terminal
      AgentPromptDag.paths_to(g, :START, :PLACE_PLAIN)

      # Query node metadata
      AgentPromptDag.node_info(g, :CLASSIFY)

      # Query outgoing edges from a node
      AgentPromptDag.out_edges(g, :DETECT_TRANSFORM)

      # Free the graph when done
      :digraph.delete(g)

  ## Node categories

  - `:entry`       — starting point of the reasoning process
  - `:inspection`  — evidence-collection: examines a property of the function
  - `:decision`    — branching point with labelled outgoing edges
  - `:constraint`  — governing rule applied during classification
  - `:routing`     — intermediate step that normalises or redirects
  - `:terminal`    — final placement recommendation
  - `:output`      — response-format or operating-standard requirement

  ## Acyclicity

  The graph is created with `:digraph.new([:acyclic])`.  Any attempt to add
  an edge that would create a cycle raises `{:error, {:bad_edge, path}}` at
  graph-build time, providing a compile-time-equivalent guarantee that the
  DAG property is preserved.
  """

  # ---------------------------------------------------------------------------
  # Node definitions
  # Each entry: {id :: atom, label :: String.t(), category :: atom}
  # ---------------------------------------------------------------------------
  @nodes [
    # Entry
    {:START, "Receive code to refactor", :entry},

    # Framing / constraint
    {:CORE_OBJ,
     "Core Objective — small · explicit · composable · idiomatic · honest about side-effects · Ash-aligned",
     :constraint},
    {:PRIME_RULE,
     "Prime Rule — judge by shape, not name: input · output · side-effect boundary",
     :constraint},

    # Inspection pipeline
    {:INSPECT_IN,
     "Inspect Inputs — data shape · raw params vs typed structs · mixed concerns? · too many unrelated inputs?",
     :inspection},
    {:INSPECT_OUT,
     "Inspect Outputs — return shape · plain value vs tagged tuple vs changeset · stability · predictability",
     :inspection},
    {:DETECT_TRANSFORM, "Detect Transformation — mostly transforming data?", :decision},
    {:DETECT_FX,
     "Detect Side Effects — DB · Ash actions · messaging · external services · file/net ops?",
     :decision},
    {:ISOLATE_FX, "Isolate Effect — keep surrounding logic thin", :routing},
    {:ANALYZE_BRANCH,
     "Analyze Branching — branches on: input shape · state · rule · outcome",
     :inspection},
    {:PREFER_PATTERNS,
     "Prefer Pattern Matching — multiple fn heads · guards · tagged tuples · avoid nested case",
     :routing},
    {:ANALYZE_NAMING,
     "Analyze Naming — is context (module · types · return shape) clear enough for a generic name?",
     :inspection},

    # Constraint nodes
    {:SHAPE_DOCTRINE,
     "Function-Shape Doctrine — understandable from module + name + arity + params + return",
     :constraint},
    {:REFACTOR_HEURISTICS,
     "Refactor Heuristics — 9 shape-driven rules: orchestration vs transformation vs entity rules",
     :constraint},
    {:CODE_STYLE,
     "Code Style Rules — small fns · pattern-match first · pipelines when readable · no nested case",
     :constraint},
    {:ASH_EXPECT,
     "Ash-specific Expectations — resource boundaries · action naming · validations · policies · domain entry points",
     :constraint},
    {:BOUNDARY_MODEL,
     "Boundary Mental Model — Resource=entity rules · Domain=business goals · Plain=transformation",
     :constraint},

    # Classification
    {:CLASSIFY,
     "Classify Function — orchestration? entity rule? pure transformation? uncertain?",
     :decision},

    # Fallback
    {:DECISION_RULE,
     "Decision Rule — when uncertain, choose simpler shapes + clearer Ash boundaries",
     :routing},

    # Validation
    {:REVIEW,
     "Review Discipline — per function: shape · effect type · orchestration? · entity rule? · placement correct?",
     :routing},

    # Terminal recommendations
    {:PLACE_RESOURCE,
     "Place in Ash Resource — entity rules · validations · changes · actions · policies · persistence",
     :terminal},
    {:PLACE_DOMAIN,
     "Place in Domain Module — business capabilities · orchestration · coordination · public entry points",
     :terminal},
    {:PLACE_PLAIN,
     "Place in Plain Elixir Module — pure transformation · normalisation · shape conversion · non-Ash helpers",
     :terminal},

    # Output requirements
    {:OUTPUT_FORMAT,
     "Required Output Format — 1:boundary changes 2:classification 3:code 4:assumptions 5:preserved behaviour",
     :output},
    {:FINAL_STD,
     "Final Operating Standard — stable shapes · obvious boundaries · idiomatic Elixir + Ash · cheap future change · low entropy",
     :output}
  ]

  # ---------------------------------------------------------------------------
  # Edge definitions
  # Each entry: {from :: atom, to :: atom, label :: String.t()}
  # ---------------------------------------------------------------------------
  @edges [
    # Framing
    {:START, :CORE_OBJ, "frames"},
    {:START, :PRIME_RULE, "frames"},

    # Prime rule / objective enable inspection
    {:PRIME_RULE, :INSPECT_IN, "shape-first inspection"},
    {:CORE_OBJ, :INSPECT_IN, "governs"},

    # Inspection pipeline
    {:INSPECT_IN, :INSPECT_OUT, "next"},
    {:INSPECT_OUT, :DETECT_TRANSFORM, "next"},

    # Transformation early-exit
    {:DETECT_TRANSFORM, :PLACE_PLAIN, "yes → pure fn"},
    {:DETECT_TRANSFORM, :DETECT_FX, "no → check effects"},

    # Side-effect branch
    {:DETECT_FX, :ISOLATE_FX, "yes → isolate"},
    {:DETECT_FX, :ANALYZE_BRANCH, "no → continue"},
    {:ISOLATE_FX, :ANALYZE_BRANCH, "continue"},

    # Branching and naming
    {:ANALYZE_BRANCH, :PREFER_PATTERNS, "apply"},
    {:PREFER_PATTERNS, :ANALYZE_NAMING, "next"},
    {:ANALYZE_NAMING, :CLASSIFY, "feeds"},

    # Constraints converge on classification
    {:SHAPE_DOCTRINE, :CLASSIFY, "constrains"},
    {:REFACTOR_HEURISTICS, :CLASSIFY, "constrains"},
    {:CODE_STYLE, :CLASSIFY, "constrains"},
    {:ASH_EXPECT, :CLASSIFY, "constrains"},
    {:BOUNDARY_MODEL, :CLASSIFY, "constrains"},

    # Classification routes
    {:CLASSIFY, :PLACE_DOMAIN, "orchestration / coordination"},
    {:CLASSIFY, :PLACE_RESOURCE, "entity rule / persistence"},
    {:CLASSIFY, :PLACE_PLAIN, "pure transformation"},
    {:CLASSIFY, :DECISION_RULE, "uncertain"},

    # Decision rule fallback
    {:DECISION_RULE, :PLACE_DOMAIN, "domain fit"},
    {:DECISION_RULE, :PLACE_RESOURCE, "resource fit"},
    {:DECISION_RULE, :PLACE_PLAIN, "simplest shape"},

    # All terminals feed review
    {:PLACE_RESOURCE, :REVIEW, "validate"},
    {:PLACE_DOMAIN, :REVIEW, "validate"},
    {:PLACE_PLAIN, :REVIEW, "validate"},

    # Output
    {:REVIEW, :OUTPUT_FORMAT, "structure response"},
    {:OUTPUT_FORMAT, :FINAL_STD, "governed by"}
  ]

  # ---------------------------------------------------------------------------
  # Public API
  # ---------------------------------------------------------------------------

  @doc """
  Builds and returns an Erlang `:digraph` graph representing the full DAG.

  The graph is created with the `:acyclic` option so that any future edge
  that would introduce a cycle is rejected at runtime.

  ## Important

  The caller is responsible for freeing the graph with `:digraph.delete/1`
  when it is no longer needed.

      g = AgentPromptDag.build()
      # ... use the graph ...
      :digraph.delete(g)
  """
  @spec build() :: :digraph.graph()
  def build do
    g = :digraph.new([:acyclic])

    for {id, label, category} <- @nodes do
      :digraph.add_vertex(g, id, %{label: label, category: category})
    end

    for {from, to, label} <- @edges do
      case :digraph.add_edge(g, from, to, label) do
        {:error, reason} ->
          raise "Failed to add edge #{from} → #{to}: #{inspect(reason)}"

        _edge ->
          :ok
      end
    end

    g
  end

  @doc """
  Returns the nodes of the graph in topological order.

  Nodes are ordered so that for every directed edge `u → v`, `u` appears
  before `v` in the list.  Returns `:not_acyclic` if the graph is not a DAG
  (should never happen with this module since `:digraph.new([:acyclic])`
  enforces it).
  """
  @spec topsort(:digraph.graph()) :: [atom()] | :not_acyclic
  def topsort(g) do
    case :digraph_utils.topsort(g) do
      false -> :not_acyclic
      order -> order
    end
  end

  @doc """
  Returns all nodes reachable from `vertex`, including `vertex` itself.
  """
  @spec reachable(:digraph.graph(), atom()) :: [atom()]
  def reachable(g, vertex) do
    :digraph_utils.reachable([vertex], g)
  end

  @doc """
  Returns the label map for a given node, e.g.:

      %{label: "Classify Function …", category: :decision}
  """
  @spec node_info(:digraph.graph(), atom()) :: map() | nil
  def node_info(g, vertex) do
    case :digraph.vertex(g, vertex) do
      {^vertex, info} -> info
      false -> nil
    end
  end

  @doc """
  Returns all outgoing edges from `vertex` as a list of
  `{edge_id, from, to, label}` tuples.
  """
  @spec out_edges(:digraph.graph(), atom()) :: [{term(), atom(), atom(), String.t()}]
  def out_edges(g, vertex) do
    g
    |> :digraph.out_edges(vertex)
    |> Enum.map(&:digraph.edge(g, &1))
  end

  @doc """
  Returns all incoming edges to `vertex` as a list of
  `{edge_id, from, to, label}` tuples.
  """
  @spec in_edges(:digraph.graph(), atom()) :: [{term(), atom(), atom(), String.t()}]
  def in_edges(g, vertex) do
    g
    |> :digraph.in_edges(vertex)
    |> Enum.map(&:digraph.edge(g, &1))
  end

  @doc """
  Returns all simple paths from `source` to `destination`.

  > #### Destructive operation {: .warning}
  >
  > This function removes edges from the graph during traversal to enumerate
  > multiple paths.  **Always pass a fresh graph** (or a dedicated copy) when
  > calling this function — do not reuse the graph afterwards.  The script
  > entrypoint below uses a separate `g2 = AgentPromptDag.build()` for exactly
  > this reason.

  Uses DFS via `:digraph.get_path/3` (which finds the first path), then
  progressively removes the last edge of each discovered path to force the
  search to find a different route on the next call.  For DAGs with bounded
  fan-out this is practical; for very large graphs prefer a purpose-built
  traversal.
  """
  @spec paths_to(:digraph.graph(), atom(), atom()) :: [[atom()]]
  def paths_to(g, source, destination) do
    collect_paths(g, source, destination, [])
  end

  @doc """
  Returns only the terminal nodes (placement recommendations).
  """
  @spec terminals(:digraph.graph()) :: [atom()]
  def terminals(g) do
    g
    |> :digraph.vertices()
    |> Enum.filter(fn v ->
      case node_info(g, v) do
        %{category: :terminal} -> true
        _ -> false
      end
    end)
  end

  @doc """
  Returns all nodes of a given category.

  Categories: `:entry`, `:inspection`, `:decision`, `:constraint`, `:routing`,
  `:terminal`, `:output`.
  """
  @spec nodes_by_category(:digraph.graph(), atom()) :: [atom()]
  def nodes_by_category(g, category) do
    g
    |> :digraph.vertices()
    |> Enum.filter(fn v ->
      match?(%{category: ^category}, node_info(g, v))
    end)
  end

  @doc """
  Pretty-prints the topological order with node labels and categories to stdout.
  """
  @spec print_topsort(:digraph.graph()) :: :ok
  def print_topsort(g) do
    g
    |> topsort()
    |> Enum.each(fn v ->
      %{label: label, category: cat} = node_info(g, v)
      IO.puts("  [#{cat}] #{v} — #{label}")
    end)
  end

  # ---------------------------------------------------------------------------
  # Private helpers
  # ---------------------------------------------------------------------------

  defp collect_paths(g, source, destination, acc) do
    case :digraph.get_path(g, source, destination) do
      false ->
        acc

      path ->
        new_acc = [path | acc]

        # Remove the last edge of this path to force `:digraph.get_path` to
        # find a different route on the next call, then recurse.
        case find_last_edge(g, path) do
          nil ->
            new_acc

          edge_id ->
            :digraph.del_edge(g, edge_id)
            collect_paths(g, source, destination, new_acc)
        end
    end
  end

  defp find_last_edge(_g, path) when length(path) < 2, do: nil

  defp find_last_edge(g, path) do
    second_last = Enum.at(path, -2)
    last = List.last(path)

    g
    |> :digraph.out_edges(second_last)
    |> Enum.find_value(fn edge_id ->
      case :digraph.edge(g, edge_id) do
        {^edge_id, ^second_last, ^last, _label} -> edge_id
        _ -> nil
      end
    end)
  end
end

# ---------------------------------------------------------------------------
# Script entrypoint — runs when executed directly via `elixir agent_prompt_dag.ex`
# ---------------------------------------------------------------------------
g = AgentPromptDag.build()

IO.puts("""

┌─────────────────────────────────────────────────────────────────┐
│        AGENT_PROMPT.md — Decision Framework DAG                 │
└─────────────────────────────────────────────────────────────────┘

Nodes: #{length(:digraph.vertices(g))}
Edges: #{length(:digraph.edges(g))}
Acyclic: #{:digraph_utils.is_acyclic(g)}

── Topological order ─────────────────────────────────────────────
""")

AgentPromptDag.print_topsort(g)

IO.puts("""

── Terminal nodes ─────────────────────────────────────────────────
""")

for t <- AgentPromptDag.terminals(g) do
  %{label: label} = AgentPromptDag.node_info(g, t)
  IO.puts("  #{t} — #{label}")
end

IO.puts("""

── Paths from START to PLACE_PLAIN ───────────────────────────────
""")

# Use a fresh graph for path enumeration (paths_to/3 mutates edges)
g2 = AgentPromptDag.build()

for path <- AgentPromptDag.paths_to(g2, :START, :PLACE_PLAIN) do
  IO.puts("  " <> Enum.join(Enum.map(path, &to_string/1), " → "))
end

:digraph.delete(g)
:digraph.delete(g2)
