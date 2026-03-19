defmodule IchorWeb.Components.GodModeComponents do
  use Phoenix.Component
  @moduledoc false

  attr :kill_switch_confirm_step, :atom, default: nil
  attr :agent_classes, :list, default: []
  attr :instructions_confirm_pending, :any, default: nil
  attr :instructions_banner, :any, default: nil

  def god_mode_view(assigns) do
    ~H"""
    <div id="god-mode-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-high">God Mode</h2>

      <%!-- Kill Switch Section --%>
      <div class="god-mode-panel">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-4">Kill Switch</h3>

        <%= cond do %>
          <% @kill_switch_confirm_step == :second -> %>
            <div class="space-y-3">
              <p class="text-sm text-error font-semibold">
                FINAL CONFIRMATION: This will pause ALL mesh operations.
              </p>
              <div class="flex items-center gap-2">
                <button phx-click="kill_switch_second_confirm" class="god-mode-button-danger">
                  CONFIRM KILL
                </button>
                <button
                  phx-click="kill_switch_cancel"
                  class="px-3 py-1.5 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                >
                  Cancel
                </button>
              </div>
            </div>
          <% @kill_switch_confirm_step == :first -> %>
            <div class="space-y-3">
              <p class="text-sm text-brand">Are you sure? This will pause all active agents.</p>
              <div class="flex items-center gap-2">
                <button phx-click="kill_switch_first_confirm" class="god-mode-button-danger">
                  Yes, proceed
                </button>
                <button
                  phx-click="kill_switch_cancel"
                  class="px-3 py-1.5 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                >
                  Cancel
                </button>
              </div>
            </div>
          <% true -> %>
            <button phx-click="kill_switch_click" class="god-mode-button-danger">
              Emergency Kill Switch
            </button>
        <% end %>
      </div>

      <%!-- Global Instructions Section --%>
      <div class="god-mode-panel">
        <h3 class="text-sm font-semibold text-default uppercase tracking-wider mb-4">
          Global Instructions
        </h3>

        <%!-- Banner --%>
        <%= if @instructions_banner do %>
          <% {type, message} = @instructions_banner %>
          <div class={"mb-4 p-3 rounded-lg text-sm #{if type == :success, do: "bg-success/15 text-success border border-success/30", else: "bg-error/15 text-error border border-error/30"}"}>
            {message}
          </div>
        <% end %>

        <%= if @agent_classes == [] do %>
          <p class="text-sm text-low">No agent classes registered</p>
        <% else %>
          <div class="space-y-4">
            <div :for={ac <- @agent_classes} class="god-mode-border rounded-lg p-4">
              <h4 class="text-sm font-semibold text-high mb-2">{ac}</h4>
              <form phx-submit="push_instructions_confirm">
                <input type="hidden" name="agent_class" value={ac} />
                <textarea
                  name="instructions"
                  rows="3"
                  placeholder="Enter global instructions for #{ac} agents..."
                  class="w-full bg-raised border border-border-subtle rounded px-3 py-2 text-xs text-high placeholder-muted focus:border-interactive focus:ring-0 resize-y"
                />
                <div class="mt-2 flex items-center gap-2">
                  <%= if @instructions_confirm_pending == ac do %>
                    <button type="submit" class="god-mode-button-danger text-xs">
                      Confirm Push
                    </button>
                    <button
                      type="button"
                      phx-click="push_instructions_cancel"
                      class="px-3 py-1.5 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                    >
                      Cancel
                    </button>
                  <% else %>
                    <button
                      type="button"
                      phx-click="push_instructions_intent"
                      phx-value-agent_class={ac}
                      class="px-3 py-1.5 text-xs bg-highlight hover:bg-highlight text-high rounded transition"
                    >
                      Push to all
                    </button>
                  <% end %>
                </div>
              </form>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
