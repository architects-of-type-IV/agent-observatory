defmodule Observatory.Operator do
  @moduledoc """
  Unified operator messaging interface.

  All messages from the dashboard operator go through this module.
  Handles target resolution and routes through Gateway.Router for
  protocol-agnostic, exactly-once delivery.

  Targets:
    - `"agent:<session_id>"` or `"session:<session_id>"` -- single agent
    - `"team:<name>"` -- all members of a team
    - `"fleet:all"` -- all active agents
    - raw session_id string -- treated as agent target
  """

  alias Observatory.Gateway.Router

  @from "operator"

  @doc """
  Send a message to any target. Returns `{:ok, delivered_count}` or `{:error, reason}`.
  """
  def send(target, content, opts \\ []) when is_binary(target) and is_binary(content) do
    channel = normalize_target(target)
    msg_type = Keyword.get(opts, :type, :text)
    metadata = Keyword.get(opts, :metadata, %{})

    payload = %{
      content: content,
      from: @from,
      type: msg_type,
      metadata: metadata
    }

    Router.broadcast(channel, payload)
  end

  defp normalize_target("agent:" <> _ = channel), do: channel
  defp normalize_target("session:" <> _ = channel), do: channel
  defp normalize_target("team:" <> _ = channel), do: channel
  defp normalize_target("fleet:" <> _ = channel), do: channel
  defp normalize_target("role:" <> _ = channel), do: channel
  defp normalize_target("all_teams"), do: "fleet:all"
  defp normalize_target("lead:" <> _name), do: "role:lead"
  defp normalize_target("member:" <> sid), do: "session:#{sid}"
  # Raw session_id or agent name
  defp normalize_target(id), do: "agent:#{id}"
end
