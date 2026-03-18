defmodule Ichor.Tools.GenesisFormatter do
  @moduledoc """
  Shared projection and input-normalization helpers for Genesis tool facades.
  """

  def to_map({:ok, record}, fields) do
    emit_signal(record)

    {:ok,
     record
     |> Map.take([:id | fields])
     |> Enum.map(fn {key, value} -> {to_string(key), stringify(value)} end)
     |> Enum.reject(fn {_key, value} -> is_nil(value) end)
     |> Map.new()}
  end

  def to_map(error, _fields), do: error

  def summarize(record, fields) do
    Map.new([:id | fields], fn field ->
      {to_string(field), stringify(Map.get(record, field))}
    end)
  end

  def stringify(value) when is_atom(value), do: to_string(value)
  def stringify(value) when is_list(value), do: Enum.join(value, ", ")
  def stringify(value), do: value

  def split_csv(nil), do: []

  def split_csv(value) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end

  def parse_enum(nil, default, _mapping), do: default
  def parse_enum(value, _default, _mapping) when is_atom(value), do: value

  def parse_enum(value, default, mapping) when is_binary(value),
    do: Map.get(mapping, value, default)

  def put_if(map, _key, nil), do: map
  def put_if(map, key, value), do: Map.put(map, key, value)

  defp emit_signal(record) do
    Ichor.Signals.emit(:genesis_artifact_created, %{
      id: record.id,
      node_id: infer_node_id(record),
      type: record.__struct__ |> Module.split() |> List.last() |> String.downcase()
    })
  end

  defp infer_node_id(record) do
    Map.get(record, :node_id) || Map.get(record, :phase_id) || Map.get(record, :section_id) ||
      Map.get(record, :task_id)
  end
end
