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
      os_pid: nil,
      channels: %{tmux: nil, ssh_tmux: nil, mailbox: session_id, webhook: nil}
    }
  end

  @doc "Abbreviate a session ID for display. UUIDs get truncated to 8 chars; human-readable names pass through."
  @spec short_id(String.t() | nil) :: String.t()
  def short_id(nil), do: "?"

  def short_id(id) when is_binary(id) do
    if uuid?(id), do: String.slice(id, 0, 8), else: id
  end

  @doc "Check if a string looks like a UUID (36 chars with dash at position 8). Cheap guard, no parsing."
  @spec uuid?(String.t()) :: boolean()
  def uuid?(
        <<_::binary-size(8), ?-, _::binary-size(4), ?-, _::binary-size(4), ?-, _::binary-size(4),
          ?-, _::binary-size(12)>>
      ), do: true

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
