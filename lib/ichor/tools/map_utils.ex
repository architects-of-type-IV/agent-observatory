defmodule Ichor.Tools.MapUtils do
  @moduledoc """
  Shared map helpers for tool action modules.
  """

  @doc """
  Puts `key => value` into `map` only when value is non-nil, non-empty string,
  and non-empty list. Returns the map unchanged otherwise.
  """
  @spec maybe_put(map(), term(), term()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)
end
