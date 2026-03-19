defmodule Ichor.Gateway.Target do
  @moduledoc """
  Canonical gateway target normalization and parsing.
  """

  @spec normalize(String.t()) :: String.t()
  def normalize("agent:" <> _ = channel), do: channel
  def normalize("session:" <> _ = channel), do: channel
  def normalize("team:" <> _ = channel), do: channel
  def normalize("fleet:" <> _ = channel), do: channel
  def normalize("role:" <> _ = channel), do: channel
  def normalize("all"), do: "fleet:all"
  def normalize("all_teams"), do: "fleet:all"
  def normalize("lead:" <> _name), do: "role:lead"
  def normalize("member:" <> sid), do: "session:#{sid}"
  def normalize(id), do: "agent:#{id}"

  @spec extract_id(String.t()) :: String.t()
  def extract_id("agent:" <> id), do: id
  def extract_id("session:" <> id), do: id
  def extract_id("member:" <> id), do: id
  def extract_id("role:" <> id), do: id
  def extract_id(raw), do: raw

  @spec kind(String.t()) :: :agent | :team | :fleet | :role | :session | :unknown
  def kind("agent:" <> _), do: :agent
  def kind("session:" <> _), do: :session
  def kind("team:" <> _), do: :team
  def kind("fleet:" <> _), do: :fleet
  def kind("role:" <> _), do: :role
  def kind(_), do: :unknown
end
