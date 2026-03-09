defmodule Ichor.Gateway.AgentRegistry.AgentEntry do
  @moduledoc """
  Default agent map constructor and shared helpers.

  The agent entry is a plain map representing a single agent in the
  ETS-backed registry. All modules that create or query agent entries
  use this shared definition to stay consistent.
  """

  @doc "Build a default agent entry for a given session ID."
  @spec new(String.t()) :: map()
  def new(session_id) do
    short = short_id(session_id)

    %{
      id: short,
      short_name: short,
      session_id: session_id,
      host: "local",
      parent_id: nil,
      team: nil,
      role: :standalone,
      status: :active,
      model: nil,
      cwd: nil,
      current_tool: nil,
      started_at: DateTime.utc_now(),
      last_event_at: DateTime.utc_now(),
      channels: %{tmux: nil, ssh_tmux: nil, mailbox: session_id, webhook: nil}
    }
  end

  @doc "Truncate a session ID to its first 8 characters."
  @spec short_id(String.t()) :: String.t()
  def short_id(session_id) when is_binary(session_id), do: String.slice(session_id, 0, 8)

  @doc "Check if a string is a valid UUID."
  @spec uuid?(String.t()) :: boolean()
  def uuid?(str) when is_binary(str), do: match?({:ok, _}, Ecto.UUID.cast(str))
  def uuid?(_), do: false

  @doc """
  Map a role string to an atom. Used by both hook events and team sync.

  Bounded to known role strings -- unknown inputs become `:worker`.
  """
  @spec role_from_string(String.t() | nil) :: atom()
  def role_from_string(nil), do: :standalone
  def role_from_string("team-lead"), do: :lead
  def role_from_string("lead"), do: :lead
  def role_from_string("coordinator"), do: :coordinator
  def role_from_string(_), do: :worker
end
