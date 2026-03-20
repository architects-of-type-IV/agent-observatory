defmodule Ichor.Projects.DateUtils do
  @moduledoc false

  @doc """
  Parse an ISO 8601 timestamp string to a DateTime.

  Accepts both UTC (`Z`-suffixed) and naive ISO strings.
  Returns `nil` for blank, non-string, or unparseable input.
  """
  @spec parse_timestamp(term()) :: DateTime.t() | nil
  def parse_timestamp(""), do: nil

  def parse_timestamp(str) when is_binary(str) do
    str = String.replace(str, "Z", "")

    case DateTime.from_iso8601(str <> "Z") do
      {:ok, dt, _} ->
        dt

      _ ->
        case NaiveDateTime.from_iso8601(str) do
          {:ok, ndt} -> DateTime.from_naive!(ndt, "Etc/UTC")
          _ -> nil
        end
    end
  end

  def parse_timestamp(_), do: nil
end
