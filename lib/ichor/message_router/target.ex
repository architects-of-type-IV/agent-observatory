defmodule Ichor.MessageRouter.Target do
  @moduledoc """
  Pure target resolution. Parses target strings into typed tuples.
  No side effects, no process lookups -- just pattern matching.
  """

  @type t ::
          {:agent, String.t()}
          | {:session, String.t()}
          | {:team, String.t()}
          | {:fleet, :all}
          | {:role, String.t()}

  @spec resolve(String.t()) :: t()
  def resolve("team:" <> name), do: {:team, name}
  def resolve("fleet:all"), do: {:fleet, :all}
  def resolve("role:" <> role), do: {:role, role}
  def resolve("session:" <> sid), do: {:session, sid}
  def resolve("agent:" <> id), do: {:agent, id}
  def resolve(id) when is_binary(id), do: {:agent, id}
end
