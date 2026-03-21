defmodule Ichor.Util do
  @moduledoc "Shared utility functions for argument coercion, parsing, and map building."

  @spec blank_to_nil(String.t() | nil) :: String.t() | nil
  def blank_to_nil(""), do: nil
  def blank_to_nil(value), do: value

  @spec empty_to_nil(list() | nil) :: list() | nil
  def empty_to_nil([]), do: nil
  def empty_to_nil(value), do: value

  @spec maybe_put(map(), atom() | String.t(), any()) :: map()
  def maybe_put(map, _key, nil), do: map
  def maybe_put(map, key, value), do: Map.put(map, key, value)

  @spec split_csv(String.t() | nil) :: [String.t()]
  def split_csv(nil), do: []

  def split_csv(value) when is_binary(value) do
    value |> String.split(",") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @spec split_lines(String.t() | nil) :: [String.t()]
  def split_lines(nil), do: []

  def split_lines(value) when is_binary(value) do
    value |> String.split("\n") |> Enum.map(&String.trim/1) |> Enum.reject(&(&1 == ""))
  end

  @spec parse_artifact_status(String.t() | atom() | nil) :: atom() | nil
  def parse_artifact_status(nil), do: nil
  def parse_artifact_status(""), do: nil
  def parse_artifact_status(value) when is_atom(value), do: value
  def parse_artifact_status("pending"), do: :pending
  def parse_artifact_status("proposed"), do: :proposed
  def parse_artifact_status("accepted"), do: :accepted
  def parse_artifact_status("rejected"), do: :rejected
  def parse_artifact_status(_value), do: :pending

  @spec parse_mode(String.t()) :: atom()
  def parse_mode("discover"), do: :discover
  def parse_mode("define"), do: :define
  def parse_mode("build"), do: :build
  def parse_mode("gate_a"), do: :gate_a
  def parse_mode("gate_b"), do: :gate_b
  def parse_mode("gate_c"), do: :gate_c
  def parse_mode(value), do: raise("unknown mode: #{value}")

  @doc "Format duration in seconds as compact string: 42s / 5m / 1h30m."
  @spec session_duration_sec(integer()) :: String.t()
  def session_duration_sec(sec) when sec < 60, do: "#{sec}s"
  def session_duration_sec(sec) when sec < 3600, do: "#{div(sec, 60)}m"
  def session_duration_sec(sec), do: "#{div(sec, 3600)}h#{rem(div(sec, 60), 60)}m"

  @doc "Extract short model family name from a full model string."
  @spec short_model_name(String.t() | nil) :: String.t() | nil
  def short_model_name(nil), do: nil

  def short_model_name(model) when is_binary(model) do
    cond do
      String.contains?(model, "opus") -> "opus"
      String.contains?(model, "sonnet") -> "sonnet"
      String.contains?(model, "haiku") -> "haiku"
      true -> model |> String.split("-") |> List.first() || model
    end
  end
end
