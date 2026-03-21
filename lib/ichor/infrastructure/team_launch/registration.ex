defmodule Ichor.Infrastructure.TeamLaunch.Registration do
  @moduledoc """
  Registers all agents for a newly-created team.

  Wraps `Ichor.Infrastructure.Registration.register/2` calls with the
  `session:window_name` tmux target convention used by team agents.
  """

  alias Ichor.Infrastructure.Registration

  @doc "Register every agent in `spec` using the team's tmux session."
  @spec register_all(map()) :: :ok | {:error, term()}
  def register_all(%{session: session, agents: agents}) do
    Enum.reduce_while(agents, :ok, fn agent, :ok ->
      case Registration.register(agent, "#{session}:#{agent.window_name}") do
        {:ok, _result} -> {:cont, :ok}
        {:error, reason} -> {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Register a single agent into an existing `session`."
  @spec register_one(map(), String.t()) :: {:ok, term()} | {:error, term()}
  def register_one(agent, session) do
    Registration.register(%{agent | session: session}, "#{session}:#{agent.window_name}")
  end
end
