defmodule AgentPromptProtocol.AgentId do
  @moduledoc """
  Typed agent identifier over structured session id strings.

  Session ids carry meaning — `"pipeline-abc123-builder"` says which kind of run
  an agent belongs to, which run, and what role it plays. Parsing that in one
  place beats splitting strings at every call site.

  ## Format

      <kind>-<run_id>-<role>[-...]

  Anything after the role is ignored, so `"mes-abc-builder-2"` parses with role
  `"builder"`. `kind` must be one of `AgentPromptProtocol.Config.id_kinds/0`;
  unrecognised kinds fail to parse rather than producing a struct nobody
  expects.

      config :agent_prompt_protocol, id_kinds: [:mes, :pipeline, :planning]

  ## Example

      iex> {:ok, id} = AgentPromptProtocol.AgentId.parse("pipeline-abc123-builder")
      iex> {id.kind, id.run_id, id.role}
      {:pipeline, "abc123", "builder"}
  """

  alias AgentPromptProtocol.Config

  @enforce_keys [:kind, :run_id, :role, :raw]
  defstruct [:kind, :run_id, :role, :raw]

  @type t :: %__MODULE__{
          kind: atom(),
          run_id: String.t(),
          role: String.t(),
          raw: String.t()
        }

  @doc """
  Parse a session id string.

      iex> AgentPromptProtocol.AgentId.parse("mes-r1-lead")
      {:ok, %AgentPromptProtocol.AgentId{kind: :mes, run_id: "r1", role: "lead", raw: "mes-r1-lead"}}

  Returns `:error` for an unknown kind or too few segments.

      iex> AgentPromptProtocol.AgentId.parse("workshop-r1-lead")
      :error

      iex> AgentPromptProtocol.AgentId.parse("mes-r1")
      :error
  """
  @spec parse(String.t()) :: {:ok, t()} | :error
  def parse(raw) when is_binary(raw) do
    with [kind, run_id, role | _] <- String.split(raw, "-"),
         {:ok, kind_atom} <- fetch_kind(kind) do
      {:ok, %__MODULE__{kind: kind_atom, run_id: run_id, role: role, raw: raw}}
    else
      _ -> :error
    end
  end

  def parse(_), do: :error

  @doc """
  Build an id from its parts.

      iex> AgentPromptProtocol.AgentId.build(:mes, "r1", "lead") |> AgentPromptProtocol.AgentId.format()
      "mes-r1-lead"
  """
  @spec build(atom(), String.t(), String.t()) :: t()
  def build(kind, run_id, role) do
    %__MODULE__{kind: kind, run_id: run_id, role: role, raw: "#{kind}-#{run_id}-#{role}"}
  end

  @doc "The raw string form."
  @spec format(t()) :: String.t()
  def format(%__MODULE__{raw: raw}), do: raw

  @doc """
  Extract just the run id from a raw session id.

      iex> AgentPromptProtocol.AgentId.run_id("pipeline-abc123-builder")
      {:ok, "abc123"}

      iex> AgentPromptProtocol.AgentId.run_id("nonsense")
      :error
  """
  @spec run_id(String.t()) :: {:ok, String.t()} | :error
  def run_id(raw) do
    case parse(raw) do
      {:ok, %{run_id: id}} -> {:ok, id}
      :error -> :error
    end
  end

  @doc """
  Whether a raw string is a well-formed agent id.

      iex> AgentPromptProtocol.AgentId.valid?("mes-r1-lead")
      true
  """
  @spec valid?(String.t()) :: boolean()
  def valid?(raw), do: match?({:ok, _}, parse(raw))

  # Compare against the configured kinds by string rather than using
  # String.to_existing_atom/1, which would depend on whether some unrelated
  # module happened to have created the atom already.
  defp fetch_kind(kind) do
    case Enum.find(Config.id_kinds(), &(Atom.to_string(&1) == kind)) do
      nil -> :error
      atom -> {:ok, atom}
    end
  end
end
