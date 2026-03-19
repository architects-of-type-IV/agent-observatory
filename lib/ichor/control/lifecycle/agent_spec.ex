defmodule Ichor.Control.Lifecycle.AgentSpec do
  @moduledoc """
  Explicit runtime spec for launching a single tmux-backed agent.
  """

  @enforce_keys [:name, :window_name, :agent_id, :cwd, :session]
  defstruct [
    :name,
    :window_name,
    :agent_id,
    :capability,
    :model,
    :cwd,
    :team_name,
    :session,
    :prompt,
    metadata: %{}
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          window_name: String.t(),
          agent_id: String.t(),
          capability: String.t() | nil,
          model: String.t() | nil,
          cwd: String.t(),
          team_name: String.t() | nil,
          session: String.t(),
          prompt: String.t() | nil,
          metadata: map()
        }

  @doc "Build an AgentSpec from an attrs map. Raises `ArgumentError` on missing required keys."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    %__MODULE__{
      name: fetch!(attrs, :name),
      window_name: fetch!(attrs, :window_name),
      agent_id: fetch!(attrs, :agent_id),
      capability: fetch(attrs, :capability, "builder"),
      model: fetch(attrs, :model, "sonnet"),
      cwd: fetch!(attrs, :cwd),
      team_name: fetch(attrs, :team_name),
      session: fetch!(attrs, :session),
      prompt: fetch(attrs, :prompt, ""),
      metadata: fetch(attrs, :metadata, %{})
    }
  end

  defp fetch!(attrs, key) do
    case fetch(attrs, key) do
      nil -> raise ArgumentError, "missing lifecycle agent spec field #{inspect(key)}"
      value -> value
    end
  end

  defp fetch(attrs, key, default \\ nil) do
    Map.get(attrs, key, Map.get(attrs, to_string(key), default))
  end
end
