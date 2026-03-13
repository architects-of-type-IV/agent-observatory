defmodule Ichor.MapHelpers do
  @moduledoc false

  @doc "Put key/value into map, skipping nil, empty string, and empty list values."
  @spec maybe_put(map(), term(), term()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, _key, ""), do: map
  def maybe_put(map, _key, []), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)
end
