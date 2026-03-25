defmodule IchorWeb.DashboardSpawnHandlers do
  @moduledoc """
  Handles agent spawning and stopping events.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

  alias Ichor.Orchestration.AgentLaunch

  def dispatch("spawn_agent", params, socket) do
    opts =
      %{
        name: params["name"],
        capability: params["capability"] || "builder",
        model: params["model"] || "sonnet",
        cwd: params["cwd"],
        team_name: params["team_name"]
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) || v == "" end)
      |> Map.new()

    case AgentLaunch.spawn(opts) do
      {:ok, info} ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "Spawned #{info.name}",
          type: "success"
        })

      {:error, reason} ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "Spawn failed: #{inspect(reason)}",
          type: "error"
        })
    end
  end

  def dispatch("stop_spawned_agent", %{"session" => session_name}, socket) do
    :ok = AgentLaunch.stop(session_name)

    Phoenix.LiveView.push_event(socket, "toast", %{
      message: "Stopping #{session_name}",
      type: "success"
    })
  end
end
