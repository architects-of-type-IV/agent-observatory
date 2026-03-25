defmodule IchorWeb.Components.Primitives.AgentInfoList do
  @moduledoc """
  Reusable dl key-value block for agent metadata.

  Renders Status, Model, Role, Team, CWD, and optional extended fields
  (Name, Type, Uptime, Events, Channels) with consistent text-[11px] body size
  and text-low/text-high label/value colours.
  """

  use Phoenix.Component

  import IchorWeb.Presentation, only: [member_status_text_class: 1]

  @doc """
  Renders a `<dl>` with key-value rows for the given agent map.

  Rows are omitted when the corresponding field is nil/absent.

  ## Attributes

  - `agent`  – agent map with status, model, role, team_name/team, cwd, etc.
  - `class`  – extra CSS classes applied to the outer `<dl>`
  """
  attr :agent, :map, required: true
  attr :class, :string, default: ""

  def agent_info_list(assigns) do
    ~H"""
    <dl class={"space-y-1 text-[11px] #{@class}"}>
      <div :if={@agent[:name]} class="flex justify-between">
        <dt class="text-low">Name</dt>
        <dd class="text-high">{@agent[:name]}</dd>
      </div>
      <div :if={@agent[:agent_type]} class="flex justify-between">
        <dt class="text-low">Type</dt>
        <dd class="text-high">{@agent[:agent_type]}</dd>
      </div>
      <div class="flex justify-between">
        <dt class="text-low">Status</dt>
        <dd class={member_status_text_class(@agent[:status] || :unknown)}>
          {@agent[:status] || :unknown}
        </dd>
      </div>
      <div :if={@agent[:model]} class="flex justify-between">
        <dt class="text-low">Model</dt>
        <dd class="text-interactive">{@agent[:model]}</dd>
      </div>
      <div :if={@agent[:role]} class="flex justify-between">
        <dt class="text-low">Role</dt>
        <dd class="text-high">{@agent[:role]}</dd>
      </div>
      <div :if={team_name(@agent)} class="flex justify-between">
        <dt class="text-low">Team</dt>
        <dd class="text-high">{team_name(@agent)}</dd>
      </div>
      <div :if={@agent[:cwd]} class="flex justify-between">
        <dt class="text-low">cwd</dt>
        <dd class="text-high font-mono truncate max-w-[200px]" title={to_string(@agent[:cwd])}>
          {Path.basename(to_string(@agent[:cwd]))}
        </dd>
      </div>
      <div :if={@agent[:uptime]} class="flex justify-between">
        <dt class="text-low">Uptime</dt>
        <dd class="text-high">{@agent[:uptime]}</dd>
      </div>
      <div :if={@agent[:event_count]} class="flex justify-between">
        <dt class="text-low">Events</dt>
        <dd class="text-high">{@agent[:event_count]}</dd>
      </div>
      <div :if={active_channels(@agent)} class="flex justify-between">
        <dt class="text-low">Channels</dt>
        <dd class="text-default font-mono text-[10px]">{active_channels(@agent)}</dd>
      </div>
    </dl>
    """
  end

  # Resolves team name from either a preloaded team struct or the map field.
  defp team_name(%{team_name: name}) when is_binary(name) and name != "", do: name
  defp team_name(%{team: %{name: name}}) when is_binary(name), do: name
  defp team_name(%{team: name}) when is_binary(name) and name != "", do: name
  defp team_name(_), do: nil

  defp active_channels(%{channels: channels}) when is_map(channels) do
    keys =
      channels
      |> Map.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.keys()
      |> Enum.join(", ")

    if keys == "", do: nil, else: keys
  end

  defp active_channels(_), do: nil
end
