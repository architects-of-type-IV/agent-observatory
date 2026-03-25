defmodule IchorWeb.Components.Agent.AgentDetailPanel do
  @moduledoc """
  Right-hand detail panel for a selected agent in the Fleet Control view.

  Renders: agent info, recent messages, action buttons, and a direct-message form.
  Uses agent_info_list for the metadata block.
  """

  use Phoenix.Component

  import IchorWeb.UI, only: [button: 1, input: 1]
  import IchorWeb.Components.Primitives.AgentActions
  import IchorWeb.Components.Primitives.AgentInfoList
  import IchorWeb.Components.Primitives.CloseButton
  alias IchorWeb.Components.FleetHelpers, as: FH

  @doc """
  Renders the agent detail panel for a selected fleet agent.
  """
  attr :agent, :map, required: true
  attr :agent_id, :string, required: true
  attr :teams, :list, default: []
  attr :messages, :list, default: []
  attr :names, :map, default: %{}
  attr :agent_filter, :list, default: []

  def agent_detail_panel(assigns) do
    sel_name = assigns.agent[:name] || assigns.agent_id
    sel_session_id = assigns.agent[:session_id]
    sel_tmux = assigns.agent[:tmux_session]
    agent_msgs = agent_messages(assigns.messages, assigns.agent_id, sel_session_id)

    assigns =
      assigns
      |> Phoenix.Component.assign(:sel_name, sel_name)
      |> Phoenix.Component.assign(:sel_session_id, sel_session_id)
      |> Phoenix.Component.assign(:sel_tmux, sel_tmux)
      |> Phoenix.Component.assign(:agent_msgs, agent_msgs)

    ~H"""
    <div class="px-3 py-1.5 border-b border-border flex items-center justify-between shrink-0">
      <h3 class="text-[11px] font-semibold text-high">{@sel_name}</h3>
      <.close_button on_click="clear_command_selection" />
    </div>
    <div class="flex-1 overflow-y-auto">
      <%!-- Info --%>
      <div class="px-3 py-2.5 border-b border-border/50">
        <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider mb-2">Info</h4>
        <.agent_info_list agent={@agent} />
      </div>

      <%!-- Recent Messages --%>
      <div :if={@agent_msgs != []} class="px-3 py-2.5 border-b border-border/50">
        <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider mb-2">
          Recent Messages
        </h4>
        <div :for={msg <- @agent_msgs} class="mb-2.5">
          <div class="flex items-center gap-1.5 mb-0.5">
            <% is_sent = msg.from == @agent_id %>
            <span class={"text-[9px] #{if is_sent, do: "text-interactive", else: "text-success"}"}>
              {if is_sent, do: "sent", else: "recv"}
            </span>
            <span class="text-[9px] text-low">{if is_sent, do: "to", else: "from"}</span>
            <span class="text-[9px] text-high">
              {FH.resolve_label(if(is_sent, do: msg.to, else: msg.from), @names)}
            </span>
            <span class="flex-1" />
            <span class="text-[9px] text-muted font-mono">
              {FH.format_timestamp(msg.timestamp)}
            </span>
          </div>
          <p class="text-[10px] text-default leading-relaxed pl-0.5 line-clamp-2">
            {msg.content}
          </p>
        </div>
      </div>

      <%!-- Actions --%>
      <div class="px-3 py-2.5 border-b border-border/50">
        <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider mb-2">
          Actions
        </h4>
        <div class="flex flex-wrap gap-1.5">
          <.button
            phx-click="open_agent_slideout"
            phx-value-session_id={@agent_id}
            variant="primary"
          >
            Focus
          </.button>
          <% is_traced = @agent_id in @agent_filter %>
          <button
            phx-click="trace_agent"
            phx-value-agent_id={@agent_id}
            class={"ichor-btn #{if is_traced, do: "bg-violet/15 text-violet", else: "ichor-btn-muted"}"}
          >
            {if is_traced, do: "Tracing", else: "Trace"}
          </button>
          <.agent_actions
            session_id={@sel_session_id || @agent_id}
            tmux_session={@sel_tmux}
          />
        </div>
      </div>

      <%!-- Direct Message --%>
      <div class="px-3 py-2.5">
        <h4 class="text-[10px] font-semibold text-low uppercase tracking-wider mb-2">
          Send Message
        </h4>
        <div class="text-[10px] text-muted mb-1">
          To: <span class="text-default font-mono">{@sel_name}</span>
        </div>
        <div phx-update="ignore" id={"fleet-msg-#{@agent_id}"} phx-hook="ClearFormOnSubmit">
          <form phx-submit="send_command_message" class="flex gap-1.5">
            <input type="hidden" name="to" value={@agent_id} />
            <.input
              name="content"
              placeholder={"Message #{@sel_name}..."}
              class="flex-1"
            />
            <.button type="submit" variant="primary">Send</.button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  @spec agent_messages(list(), String.t(), String.t() | nil) :: list()
  defp agent_messages(messages, agent_id, session_id) do
    ids = [agent_id, session_id] |> Enum.reject(&is_nil/1) |> MapSet.new()

    messages
    |> Enum.filter(fn m -> MapSet.member?(ids, m.from) || MapSet.member?(ids, m.to) end)
    |> Enum.take(4)
  end
end
