defmodule Ichor.Workshop.AgentId do
  @moduledoc "Typed agent identifier. Parses structured session ID strings."

  @type t :: %__MODULE__{kind: atom(), run_id: String.t(), role: String.t(), raw: String.t()}
  defstruct [:kind, :run_id, :role, :raw]

  @valid_kinds ~w(mes pipeline planning)

  @doc "Parses a structured session ID string into an AgentId struct."
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(raw) when is_binary(raw) do
    case String.split(raw, "-") do
      [kind, run_id, role | _] when kind in @valid_kinds ->
        {:ok,
         %__MODULE__{kind: String.to_existing_atom(kind), run_id: run_id, role: role, raw: raw}}

      _ ->
        :error
    end
  end

  @doc "Returns the raw string representation of the agent ID."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{raw: raw}), do: raw

  @doc "Builds a new AgentId struct from components."
  @spec build(atom(), String.t(), String.t()) :: t()
  def build(kind, run_id, role) do
    raw = "#{kind}-#{run_id}-#{role}"
    %__MODULE__{kind: kind, run_id: run_id, role: role, raw: raw}
  end

  @doc "Extracts the run_id from a raw agent ID string."
  @spec run_id(String.t()) :: {:ok, String.t()} | :error
  def run_id(raw) do
    case parse(raw) do
      {:ok, %{run_id: id}} -> {:ok, id}
      :error -> :error
    end
  end
end
