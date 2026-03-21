defmodule Ichor.Infrastructure.TeamLaunch.Scripts do
  @moduledoc """
  Writes prompt and launch-script files for all agents in a team spec.

  Returns a `{window_name => script_path}` map on success so subsequent
  pipeline stages can look up the script path for each agent window.
  """

  alias Ichor.Infrastructure.Tmux.Script

  @doc """
  Write agent files for every agent in `spec`.

  Returns `{:ok, scripts}` where `scripts` is a map from `window_name` to the
  absolute script path, or `{:error, reason}` if any file write fails.
  """
  @spec write_all(map()) :: {:ok, %{String.t() => String.t()}} | {:error, term()}
  def write_all(%{prompt_dir: prompt_dir, agents: agents}) do
    Enum.reduce_while(agents, {:ok, %{}}, fn agent, {:ok, acc} ->
      case Script.write_agent_files(
             prompt_dir,
             agent.window_name,
             agent.prompt || "",
             agent.model || "sonnet",
             agent.capability || "builder"
           ) do
        {:ok, %{script_path: script_path}} ->
          {:cont, {:ok, Map.put(acc, agent.window_name, script_path)}}

        {:error, reason} ->
          {:halt, {:error, reason}}
      end
    end)
  end

  @doc "Look up the script path for `window_name`. Raises if not found."
  @spec fetch!(map(), String.t()) :: String.t()
  def fetch!(scripts, window_name), do: Map.fetch!(scripts, window_name)
end
