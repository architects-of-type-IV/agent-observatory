defmodule IchorWeb.Components.RegistryComponents do
  use Phoenix.Component

  attr :agent_types, :list, default: []
  attr :route_weights, :map, default: %{}
  attr :capability_sort_field, :atom, default: :agent_type
  attr :capability_sort_dir, :atom, default: :asc
  attr :route_weight_errors, :map, default: %{}

  def registry_view(assigns) do
    sorted_types =
      sort_agent_types(
        assigns.agent_types,
        assigns.capability_sort_field,
        assigns.capability_sort_dir
      )

    assigns = assign(assigns, :sorted_types, sorted_types)

    ~H"""
    <div id="registry-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-high">Registry</h2>

      <%!-- Capability Directory --%>
      <div class="bg-base/50 border border-border rounded-lg">
        <div class="px-4 py-3 border-b border-border">
          <h3 class="text-sm font-semibold text-default uppercase tracking-wider">
            Capability Directory
          </h3>
        </div>
        <table class="w-full">
          <thead>
            <tr class="text-xs text-low uppercase">
              <th
                class="px-4 py-2 text-left cursor-pointer hover:text-high"
                phx-click="sort_capability_directory"
                phx-value-field="agent_type"
              >
                Agent Type {sort_indicator(@capability_sort_field, :agent_type, @capability_sort_dir)}
              </th>
              <th
                class="px-4 py-2 text-left cursor-pointer hover:text-high"
                phx-click="sort_capability_directory"
                phx-value-field="instance_count"
              >
                Instances {sort_indicator(
                  @capability_sort_field,
                  :instance_count,
                  @capability_sort_dir
                )}
              </th>
              <th
                class="px-4 py-2 text-left cursor-pointer hover:text-high"
                phx-click="sort_capability_directory"
                phx-value-field="capability_version"
              >
                Version {sort_indicator(
                  @capability_sort_field,
                  :capability_version,
                  @capability_sort_dir
                )}
              </th>
            </tr>
          </thead>
          <tbody>
            <%= if @sorted_types == [] do %>
              <tr>
                <td colspan="3" class="px-4 py-4 text-sm text-low text-center">
                  No agent types registered
                </td>
              </tr>
            <% else %>
              <tr :for={at <- @sorted_types} class="border-t border-border/50 hover:bg-raised/30">
                <td class="px-4 py-2 text-sm text-high">{Map.get(at, :agent_type, "unknown")}</td>
                <td class="px-4 py-2 text-sm text-default">{Map.get(at, :instance_count, 0)}</td>
                <td class="px-4 py-2 text-sm font-mono text-low">
                  {Map.get(at, :capability_version, "-")}
                </td>
              </tr>
            <% end %>
          </tbody>
        </table>
      </div>

      <%!-- Routing Logic Manager --%>
      <div class="bg-base/50 border border-border rounded-lg p-4">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-4">
          Routing Logic Manager
        </h3>
        <%= if @sorted_types == [] do %>
          <p class="text-sm text-low">No agent types to configure</p>
        <% else %>
          <div class="space-y-3">
            <div :for={at <- @sorted_types} class="flex items-center gap-3">
              <span class="text-sm text-high w-32">{Map.get(at, :agent_type, "unknown")}</span>
              <form phx-submit="update_route_weight" class="flex items-center gap-2">
                <input type="hidden" name="agent_type" value={Map.get(at, :agent_type, "")} />
                <input
                  type="number"
                  name="weight"
                  value={Map.get(@route_weights, Map.get(at, :agent_type, ""), "")}
                  placeholder="0-100"
                  min="0"
                  max="100"
                  class="w-20 bg-raised border border-border-subtle rounded px-2 py-1 text-xs text-high focus:border-interactive focus:ring-0"
                />
                <button
                  type="submit"
                  class="px-2 py-1 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                >
                  Set
                </button>
              </form>
              <span
                :if={Map.get(@route_weight_errors, Map.get(at, :agent_type, ""))}
                class="text-xs text-error"
              >
                {Map.get(@route_weight_errors, Map.get(at, :agent_type, ""))}
              </span>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end

  defp sort_agent_types(types, field, dir) do
    Enum.sort_by(
      types,
      fn at -> Map.get(at, field, "") end,
      if(dir == :asc, do: :asc, else: :desc)
    )
  end

  defp sort_indicator(current_field, field, dir) do
    if current_field == field do
      if dir == :asc, do: " ↑", else: " ↓"
    else
      ""
    end
  end
end
