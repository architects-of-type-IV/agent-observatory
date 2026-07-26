defmodule WorkshopCanvas.Agent do
  @moduledoc """
  Construction and layout for a single agent slot on the canvas.

  Agents are plain maps rather than structs, because they travel straight into
  a LiveView's assigns and back out to persistence params.

  ## Why every key is always present

  `build/2` fills in every field, even when the caller supplied none. The canvas
  edits agents with map-update syntax (`%{agent | name: ...}`), which raises on a
  missing key — so an agent built from a sparse preset or a partial persisted
  record would blow up the first time someone edited it, not when it was
  created. Filling the map at construction keeps that failure impossible.
  """

  alias WorkshopCanvas.Config

  @typedoc "An agent slot."
  @type t :: %{
          id: integer(),
          agent_type_id: String.t() | nil,
          name: String.t(),
          capability: String.t(),
          model: String.t(),
          permission: String.t(),
          persona: String.t(),
          file_scope: String.t(),
          quality_gates: String.t(),
          tools: [String.t()],
          x: integer(),
          y: integer()
        }

  @keys [
    :id,
    :agent_type_id,
    :name,
    :capability,
    :model,
    :permission,
    :persona,
    :file_scope,
    :quality_gates,
    :tools,
    :x,
    :y
  ]

  @doc "The full set of keys every agent map carries."
  @spec keys() :: [atom()]
  def keys, do: @keys

  @doc """
  Build a complete agent map from partial attributes.

  ## Options

    * `:id` — slot id; taken from `attrs` when absent, else `1`
    * `:index` — position in the layout grid, used to derive `x`/`y`
    * `:default_model` — model to use when `attrs` names none

  Explicit `:x`/`:y` in `attrs` win over the grid position.
  """
  @spec build(map(), keyword()) :: t()
  def build(attrs, opts \\ []) do
    index = Keyword.get(opts, :index, 0)
    {grid_x, grid_y} = position(index)

    %{
      id: Keyword.get(opts, :id) || Map.get(attrs, :id) || 1,
      agent_type_id: Map.get(attrs, :agent_type_id),
      name: Map.get(attrs, :name) || "agent",
      capability: Map.get(attrs, :capability) || Config.default_capability(),
      model:
        Map.get(attrs, :model) || Keyword.get(opts, :default_model) || Config.default_model(),
      permission: Map.get(attrs, :permission) || Config.default_permission(),
      persona: Map.get(attrs, :persona) || "",
      file_scope: Map.get(attrs, :file_scope) || "",
      quality_gates: Map.get(attrs, :quality_gates) || Config.default_quality_gates(),
      tools: Map.get(attrs, :tools) || [],
      x: Map.get(attrs, :x) || grid_x,
      y: Map.get(attrs, :y) || grid_y
    }
  end

  @doc """
  Grid coordinates for the nth agent placed.

      iex> WorkshopCanvas.Agent.position(0)
      {40, 30}

      iex> WorkshopCanvas.Agent.position(3)
      {40, 200}
  """
  @spec position(non_neg_integer()) :: {integer(), integer()}
  def position(index) do
    columns = Config.grid_columns()

    {
      Config.grid_x_origin() + rem(index, columns) * Config.grid_x_spacing(),
      Config.grid_y_origin() + div(index, columns) * Config.grid_y_spacing()
    }
  end

  @doc """
  Fill in any keys a map is missing, leaving the ones it has alone.

  For agents loaded from persistence written by an older version of the schema.
  """
  @spec complete(map()) :: t()
  def complete(agent) when is_map(agent), do: build(agent, id: Map.get(agent, :id))
end
