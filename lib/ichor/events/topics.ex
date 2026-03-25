defmodule Ichor.Events.Topics do
  @moduledoc """
  Centralized topic string builder.

  No raw topic strings outside this module.
  """

  @spec category(atom()) :: String.t()
  def category(cat), do: "signal:#{cat}"

  @spec signal(atom(), atom()) :: String.t()
  def signal(domain, name), do: "signal:#{domain}:#{name}"

  @spec scoped(atom(), atom(), String.t()) :: String.t()
  def scoped(domain, name, scope_id), do: "signal:#{domain}:#{name}:#{scope_id}"
end
