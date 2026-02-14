defmodule ObservatoryWeb.DashboardSessionHelpers do
  @moduledoc """
  Session enrichment and derivation helpers for the Observatory Dashboard.
  Handles extracting model names, working directories, and other session metadata.
  """

  @doc """
  Extract model name from session events.
  Checks SessionStart events and fallback to model_name field.
  """
  def extract_session_model(events) do
    # Try SessionStart first
    session_start =
      events
      |> Enum.find(fn e ->
        e.hook_event_type == :SessionStart
      end)

    if session_start do
      (session_start.payload || %{})["model"] || session_start.model_name
    else
      # Fallback to first event with model_name
      Enum.find_value(events, fn e -> e.model_name || (e.payload || %{})["model"] end)
    end
  end

  @doc """
  Extract working directory from session events.
  Returns the most recent cwd.
  """
  def extract_session_cwd(events) do
    events
    |> Enum.sort_by(& &1.inserted_at, {:desc, DateTime})
    |> Enum.find_value(fn e -> e.cwd end)
  end

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

  @doc """
  Extract short model name for display.
  """
  def short_model_name(nil), do: nil

  def short_model_name(model) when is_binary(model) do
    # Extract model name without version/provider prefix
    # Examples: "claude-opus-4-6" -> "opus-4-6", "claude-sonnet-4-5-20250929" -> "sonnet-4-5"
    cond do
      String.contains?(model, "opus") -> "opus"
      String.contains?(model, "sonnet") -> "sonnet"
      String.contains?(model, "haiku") -> "haiku"
      true -> model |> String.split("-") |> List.first() || model
    end
  end
end
