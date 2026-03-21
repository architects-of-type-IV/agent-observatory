defmodule Ichor.Infrastructure.AgentMessage do
  @moduledoc """
  Helpers for normalizing and inspecting agent messages.

  A raw message may arrive as a plain string (content-only) or as a map that
  already carries structured fields.  This module ensures every message that
  enters the agent state has a stable shape before it is stored or routed.
  """

  @doc """
  Normalize an incoming message into a canonical map.

  String inputs are promoted to a full message map with sensible defaults.
  Map inputs are merged with required fields that may be missing (`id`,
  `to`, `timestamp`), leaving any caller-supplied values intact.
  """
  @spec normalize(map() | String.t(), String.t()) :: map()
  def normalize(msg, to) when is_map(msg) do
    Map.merge(
      %{id: Ecto.UUID.generate(), to: to, timestamp: DateTime.utc_now()},
      msg
    )
  end

  def normalize(content, to) when is_binary(content) do
    %{
      id: Ecto.UUID.generate(),
      to: to,
      from: "system",
      content: content,
      type: :message,
      timestamp: DateTime.utc_now()
    }
  end

  @doc """
  Extract the deliverable text content from a message map.

  Falls back to `inspect/1` so there is always something meaningful to send.
  """
  @spec content(map()) :: String.t()
  def content(msg) do
    msg[:content] || inspect(msg)
  end
end
