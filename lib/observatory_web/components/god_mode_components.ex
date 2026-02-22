defmodule ObservatoryWeb.Components.GodModeComponents do
  use Phoenix.Component

  attr :kill_switch_confirm_step, :atom, default: nil
  attr :agent_classes, :list, default: []
  attr :instructions_confirm_pending, :any, default: nil
  attr :instructions_banner, :any, default: nil

  def god_mode_view(assigns) do
    ~H"""
    <div id="god-mode-view" class="p-6 space-y-6">
      <h2 class="text-lg font-semibold text-zinc-300">God Mode</h2>

      <%!-- Kill Switch Section --%>
      <div class="god-mode-panel">
        <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-4">Kill Switch</h3>

        <%= cond do %>
          <% @kill_switch_confirm_step == :second -> %>
            <div class="space-y-3">
              <p class="text-sm text-red-400 font-semibold">FINAL CONFIRMATION: This will pause ALL mesh operations.</p>
              <div class="flex items-center gap-2">
                <button phx-click="kill_switch_second_confirm" class="god-mode-button-danger">
                  CONFIRM KILL
                </button>
                <button phx-click="kill_switch_cancel" class="px-3 py-1.5 text-xs bg-zinc-700 hover:bg-zinc-600 text-zinc-300 rounded transition">
                  Cancel
                </button>
              </div>
            </div>

          <% @kill_switch_confirm_step == :first -> %>
            <div class="space-y-3">
              <p class="text-sm text-amber-400">Are you sure? This will pause all active agents.</p>
              <div class="flex items-center gap-2">
                <button phx-click="kill_switch_first_confirm" class="god-mode-button-danger">
                  Yes, proceed
                </button>
                <button phx-click="kill_switch_cancel" class="px-3 py-1.5 text-xs bg-zinc-700 hover:bg-zinc-600 text-zinc-300 rounded transition">
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
        <h3 class="text-sm font-semibold text-zinc-400 uppercase tracking-wider mb-4">Global Instructions</h3>

        <%!-- Banner --%>
        <%= if @instructions_banner do %>
          <% {type, message} = @instructions_banner %>
          <div class={"mb-4 p-3 rounded-lg text-sm #{if type == :success, do: "bg-emerald-500/15 text-emerald-400 border border-emerald-500/30", else: "bg-red-500/15 text-red-400 border border-red-500/30"}"}>
            {message}
          </div>
        <% end %>

        <%= if @agent_classes == [] do %>
          <p class="text-sm text-zinc-500">No agent classes registered</p>
        <% else %>
          <div class="space-y-4">
            <div :for={ac <- @agent_classes} class="god-mode-border rounded-lg p-4">
              <h4 class="text-sm font-semibold text-zinc-300 mb-2">{ac}</h4>
              <form phx-submit="push_instructions_confirm">
                <input type="hidden" name="agent_class" value={ac} />
                <textarea
                  name="instructions"
                  rows="3"
                  placeholder="Enter global instructions for #{ac} agents..."
                  class="w-full bg-zinc-800 border border-zinc-700 rounded px-3 py-2 text-xs text-zinc-300 placeholder-zinc-600 focus:border-indigo-500 focus:ring-0 resize-y"
                />
                <div class="mt-2 flex items-center gap-2">
                  <%= if @instructions_confirm_pending == ac do %>
                    <button type="submit" class="god-mode-button-danger text-xs">
                      Confirm Push
                    </button>
                    <button type="button" phx-click="push_instructions_cancel" class="px-3 py-1.5 text-xs bg-zinc-700 hover:bg-zinc-600 text-zinc-300 rounded transition">
                      Cancel
                    </button>
                  <% else %>
                    <button type="button" phx-click="push_instructions_intent" phx-value-agent_class={ac} class="px-3 py-1.5 text-xs bg-zinc-700 hover:bg-zinc-600 text-zinc-300 rounded transition">
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
