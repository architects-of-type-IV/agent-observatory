defmodule WorkshopCanvas.Config do
  @moduledoc """
  Defaults for a new canvas and for newly placed agents.

      config :workshop_canvas,
        default_team_name: "alpha",
        default_strategy: "one_for_one",
        default_model: "sonnet",
        default_capability: "builder",
        default_permission: "default",
        default_quality_gates: "mix compile --warnings-as-errors",
        grid_columns: 3,
        grid_x_origin: 40,
        grid_y_origin: 30,
        grid_x_spacing: 230,
        grid_y_spacing: 170
  """

  @defaults %{
    default_team_name: "alpha",
    default_strategy: "one_for_one",
    default_model: "sonnet",
    default_capability: "builder",
    default_permission: "default",
    default_quality_gates: "mix compile --warnings-as-errors",
    grid_columns: 3,
    grid_x_origin: 40,
    grid_y_origin: 30,
    grid_x_spacing: 230,
    grid_y_spacing: 170
  }

  for {key, _} <- @defaults do
    @doc "The `#{key}` setting."
    @spec unquote(key)() :: term()
    def unquote(key)(), do: get(unquote(key))
  end

  @doc "Every default as a map."
  @spec all() :: map()
  def all, do: Map.new(@defaults, fn {key, _} -> {key, get(key)} end)

  defp get(key), do: Application.get_env(:workshop_canvas, key, Map.fetch!(@defaults, key))
end
