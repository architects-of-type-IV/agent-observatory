defmodule Ichor.Tools.Messaging do
  @moduledoc """
  Shared message-send actions used by Archon and agent-facing tool facades.
  """

  alias Ichor.Fleet.Agent, as: FleetAgent
  alias Ichor.Gateway.Router
  alias Ichor.Gateway.Target
  alias Ichor.Operator

  def send_as_operator(to, content) when is_binary(to) and is_binary(content) do
    with {:ok, delivered} <- Operator.send(to, content) do
      {:ok, %{status: "sent", to: to, delivered: delivered}}
    end
  end

  def send_as_agent(from, to, content)
      when is_binary(from) and is_binary(to) and is_binary(content) do
    channel = Target.normalize(to)

    case Target.kind(channel) do
      kind when kind in [:team, :fleet, :role, :session] ->
        broadcast(channel, from, to, content)

      _ ->
        deliver_to_agent(from, to, content)
    end
  end

  defp deliver_to_agent(from, to, content) do
    case FleetAgent.send_message(to, content, %{from: from}) do
      {:ok, _result} ->
        {:ok, %{status: "sent", to: to, delivered: 1, via: "fleet"}}

      {:error, _reason} ->
        broadcast(Target.normalize(to), from, to, content)
    end
  end

  defp broadcast(channel, from, original_to, content) do
    case Router.broadcast(channel, %{content: content, from: from}) do
      {:ok, delivered} when delivered > 0 ->
        {:ok, %{status: "sent", to: original_to, delivered: delivered}}

      {:ok, 0} ->
        {:ok,
         %{
           status: "no_recipients",
           to: original_to,
           delivered: 0,
           error: "No delivery channel found for #{original_to}. Recipient may not be registered."
         }}

      {:error, reason} ->
        {:error, "Failed to send message: #{inspect(reason)}"}
    end
  end
end
