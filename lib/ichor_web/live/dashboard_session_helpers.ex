defmodule IchorWeb.DashboardSessionHelpers do
  @moduledoc """
  Session display helpers for the Ichor Dashboard.
  Handles abbreviation and formatting of session metadata.
  """

  @doc """
  Abbreviate working directory path for display.
  Shows last 2 path segments or full path if short.
  """
  def abbreviate_cwd(nil), do: nil

  def abbreviate_cwd(cwd) when is_binary(cwd) do
    parts = String.split(cwd, "/")

    cond do
      length(parts) <= 2 -> cwd
      length(parts) == 3 -> Enum.join(Enum.take(parts, -2), "/")
      true -> ".../" <> Enum.join(Enum.take(parts, -2), "/")
    end
  end

  @doc "Extract short model family name for display."
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
