defmodule Ichor.Infrastructure.TeamSpec do
  @moduledoc """
  Explicit runtime spec for launching a multi-agent team session.
  """

  alias Ichor.Infrastructure.AgentSpec

  @enforce_keys [:team_name, :session, :cwd, :agents, :prompt_dir]
  defstruct [:team_name, :session, :cwd, :agents, :prompt_dir, metadata: %{}]

  @type t :: %__MODULE__{
          team_name: String.t(),
          session: String.t(),
          cwd: String.t(),
          agents: [AgentSpec.t()],
          prompt_dir: String.t(),
          metadata: map()
        }

  @doc "Build a TeamSpec from an attrs map. Raises `ArgumentError` on missing required keys."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      team_name: fetch!(attrs, :team_name),
      session: fetch!(attrs, :session),
      cwd: fetch!(attrs, :cwd),
      agents: fetch!(attrs, :agents),
      prompt_dir: fetch!(attrs, :prompt_dir),
      metadata: fetch(attrs, :metadata, %{})
    }
  end

  defp fetch!(attrs, key) do
    case fetch(attrs, key) do
      nil -> raise ArgumentError, "missing lifecycle team spec field #{inspect(key)}"
      value -> value
    end
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, to_string(key), default))
  end
end
