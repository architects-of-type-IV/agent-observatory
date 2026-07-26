defmodule WorkshopCanvas.Preset do
  @moduledoc """
  A named starting layout for the canvas.

  A preset is data: a team name, a strategy, a model, and the agents, spawn
  links, and comm rules to drop onto an empty canvas. Registering your own is
  the point — the one built-in preset exists to document the shape, not to be
  used.

      config :workshop_canvas, presets: %{
        "review" => %WorkshopCanvas.Preset{
          label: "Code review",
          color: "#7c3aed",
          team_name: "review",
          agents: [
            %{id: 1, name: "lead", capability: "coordinator"},
            %{id: 2, name: "reviewer", capability: "scout"}
          ],
          links: [%{from: 1, to: 2}],
          rules: [%{from: 1, to: 2, policy: "allow", via: nil}]
        }
      }

  Agent maps are filled out through `WorkshopCanvas.new_agent/2` on apply, so a
  preset only has to state what differs from the defaults.
  """

  alias WorkshopCanvas.Config

  @enforce_keys [:label]
  defstruct [
    :label,
    :team_name,
    :strategy,
    :model,
    color: "#64748b",
    agents: [],
    links: [],
    rules: []
  ]

  @type t :: %__MODULE__{
          label: String.t(),
          color: String.t(),
          team_name: String.t() | nil,
          strategy: String.t() | nil,
          model: String.t() | nil,
          agents: [map()],
          links: [map()],
          rules: [map()]
        }

  @doc """
  The one bundled preset: a coordinator that spawns a builder, talking both ways.

  It exists to document the shape and to give the tests something concrete. Real
  presets belong in your own configuration.
  """
  @spec builtin() :: %{optional(String.t()) => t()}
  def builtin do
    %{
      "pair" => %__MODULE__{
        label: "Coordinator + builder",
        color: "#0ea5e9",
        team_name: "pair",
        agents: [
          %{id: 1, name: "coordinator", capability: "coordinator"},
          %{id: 2, name: "builder", capability: "builder"}
        ],
        links: [%{from: 1, to: 2}],
        rules: [
          %{from: 1, to: 2, policy: "allow", via: nil},
          %{from: 2, to: 1, policy: "allow", via: nil}
        ]
      }
    }
  end

  @doc """
  Every registered preset, keyed by name.

  Configured presets replace the built-in map rather than merging with it, so
  a host is never stuck with an example it did not ask for.
  """
  @spec all() :: %{optional(String.t()) => t()}
  def all, do: Application.get_env(:workshop_canvas, :presets, builtin())

  @doc "Registered preset names, sorted."
  @spec names() :: [String.t()]
  def names, do: all() |> Map.keys() |> Enum.sort()

  @doc "Fetch a preset by name."
  @spec fetch(String.t()) :: {:ok, t()} | :error
  def fetch(name), do: Map.fetch(all(), name)

  @doc """
  Name, label, and colour for each preset — enough to render a picker.

      iex> [%{name: "pair"} | _] = WorkshopCanvas.Preset.ui_list()
  """
  @spec ui_list() :: [%{name: String.t(), label: String.t(), color: String.t()}]
  def ui_list do
    all()
    |> Enum.map(fn {name, preset} ->
      %{name: name, label: preset.label, color: preset.color}
    end)
    |> Enum.sort_by(& &1.name)
  end

  @doc """
  Replace the canvas contents with a preset's.

  An unknown name returns the state untouched, so a stale button in the UI
  cannot blank someone's canvas.
  """
  @spec apply(map(), String.t()) :: map()
  def apply(state, name) do
    case fetch(name) do
      {:ok, preset} -> put(state, preset)
      :error -> state
    end
  end

  defp put(state, preset) do
    model = preset.model || Config.default_model()

    agents =
      preset.agents
      |> Enum.map(&normalise/1)
      |> Enum.with_index()
      |> Enum.map(fn {attrs, index} ->
        WorkshopCanvas.Agent.build(attrs, index: index, default_model: model)
      end)

    state
    |> Map.put(:ws_team_name, preset.team_name || Config.default_team_name())
    |> Map.put(:ws_strategy, preset.strategy || Config.default_strategy())
    |> Map.put(:ws_default_model, preset.model || Config.default_model())
    |> Map.put(:ws_agents, agents)
    |> Map.put(:ws_spawn_links, Enum.map(preset.links, &normalise/1))
    |> Map.put(:ws_comm_rules, Enum.map(preset.rules, &normalise/1))
    |> Map.put(:ws_selected_agent, nil)
    |> Map.put(:ws_next_id, next_id(agents))
  end

  # Derived rather than stored: a preset that hand-maintains next_id gets it
  # wrong the moment someone edits the agent list, and the collision that
  # follows is a duplicated slot id.
  defp next_id([]), do: 1
  defp next_id(agents), do: (agents |> Enum.map(& &1.id) |> Enum.max()) + 1

  defp normalise(%{__struct__: _} = struct), do: Map.from_struct(struct)
  defp normalise(map) when is_map(map), do: map
end
