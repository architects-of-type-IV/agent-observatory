defmodule Ichor.Gateway.Router.Delivery do
  @moduledoc """
  Channel delivery execution for gateway envelopes.
  """

  @spec deliver(map(), [map()], [{module(), keyword()}]) :: non_neg_integer()
  def deliver(envelope, recipients, channels) do
    Enum.reduce(recipients, 0, fn agent, count ->
      count + deliver_to_agent(agent, envelope.payload, channels)
    end)
  end

  defp deliver_to_agent(agent, payload, channels) do
    Enum.reduce(channels, 0, fn {mod, opts}, count ->
      key = mod.channel_key()
      address = (agent[:channels] || %{})[key]
      skip? = function_exported?(mod, :skip?, 1) and mod.skip?(payload)
      deliver_via_channel(mod, opts, key, address, agent, payload, skip?, count)
    end)
  end

  defp deliver_via_channel(_mod, _opts, _key, nil, _agent, _payload, _skip?, count), do: count
  defp deliver_via_channel(_mod, _opts, _key, _address, _agent, _payload, true, count), do: count

  defp deliver_via_channel(mod, opts, key, address, agent, payload, false, count) do
    if mod.available?(address) do
      deliver_payload =
        if key == :webhook,
          do: Map.put(payload, :agent_id, agent[:session_id] || agent[:id]),
          else: payload

      count_after_deliver(mod, opts, address, deliver_payload, count)
    else
      count
    end
  end

  defp count_after_deliver(mod, opts, address, deliver_payload, count) do
    case mod.deliver(address, deliver_payload) do
      :ok -> if Keyword.get(opts, :primary, false), do: count + 1, else: count
      {:error, _} -> count
    end
  end
end
