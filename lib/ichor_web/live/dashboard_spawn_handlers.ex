defmodule IchorWeb.DashboardSpawnHandlers do
  @moduledoc """
  Handles agent spawning and stopping events.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

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

    case Ichor.Operator.spawn_agent(opts) do
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
    case Ichor.Operator.stop_agent(session_name) do
      :ok ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "Stopping #{session_name}",
          type: "success"
        })

      {:error, reason} ->
        Phoenix.LiveView.push_event(socket, "toast", %{
          message: "Stop failed: #{inspect(reason)}",
          type: "error"
        })
    end
  end
end
