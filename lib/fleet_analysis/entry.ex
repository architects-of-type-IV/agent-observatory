defmodule FleetAnalysis.Entry do
  @moduledoc """
  Identity helpers and the default shape of an agent registry entry.

  Small, but shared: hook events and team syncing both need to turn a role
  string into an atom and a session id into something displayable, and they must
  agree, or the same agent appears twice under two labels.
  """

  @roles %{
    "team-lead" => :lead,
    "lead" => :lead,
    "coordinator" => :coordinator
  }

  @doc """
  A default registry entry for a session.

  The `channels` map is the set of transports an entry can be reached on; only
  `:mailbox` is populated by default, since that is the one that works before
  anything else is wired up.
  """
  @spec new(String.t()) :: map()
  def new(session_id) do
    short = short_id(session_id)
    now = DateTime.utc_now()

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
      started_at: now,
      last_event_at: now,
      os_pid: nil,
      channels: %{tmux: nil, ssh_tmux: nil, mailbox: session_id, webhook: nil}
    }
  end

  @doc """
  Abbreviate a session id for display.

  UUIDs truncate to their first segment; human-readable names pass through
  untouched, because truncating `"pipeline-abc-builder"` would throw away the
  part that identifies it.

      iex> FleetAnalysis.Entry.short_id("550e8400-e29b-41d4-a716-446655440000")
      "550e8400"

      iex> FleetAnalysis.Entry.short_id("pipeline-abc-builder")
      "pipeline-abc-builder"

      iex> FleetAnalysis.Entry.short_id(nil)
      "?"
  """
  @spec short_id(String.t() | nil) :: String.t()
  def short_id(nil), do: "?"
  def short_id(""), do: "?"
  def short_id(id) when is_binary(id), do: if(uuid?(id), do: String.slice(id, 0, 8), else: id)
  def short_id(_), do: "?"

  @doc """
  Whether a string is shaped like a UUID.

  A cheap binary-pattern guard rather than a parse — this runs over every row of
  a rendered list.

      iex> FleetAnalysis.Entry.uuid?("550e8400-e29b-41d4-a716-446655440000")
      true

      iex> FleetAnalysis.Entry.uuid?("not-a-uuid")
      false
  """
  @spec uuid?(term()) :: boolean()
  def uuid?(
        <<_::binary-size(8), ?-, _::binary-size(4), ?-, _::binary-size(4), ?-, _::binary-size(4),
          ?-, _::binary-size(12)>>
      ),
      do: true

  def uuid?(_), do: false

  @doc """
  Map a role string to an atom.

  Bounded to known roles — an unrecognised string becomes `:worker`, never a new
  atom, since these come from user-authored team configs and unbounded
  `String.to_atom/1` on that input would leak the atom table.

      iex> FleetAnalysis.Entry.role_from_string("team-lead")
      :lead

      iex> FleetAnalysis.Entry.role_from_string("whatever")
      :worker

      iex> FleetAnalysis.Entry.role_from_string(nil)
      :standalone
  """
  @spec role_from_string(String.t() | nil) :: atom()
  def role_from_string(nil), do: :standalone
  def role_from_string(role) when is_binary(role), do: Map.get(@roles, role, :worker)
  def role_from_string(_), do: :worker
end
