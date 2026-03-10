defmodule IchorWeb.Components.ArchonComponents.ChatPanel do
  @moduledoc false

  use Phoenix.Component

  import IchorWeb.Markdown, only: [render: 1]

  attr :messages, :list, required: true
  attr :loading, :boolean, default: false

  def chat_panel(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div id="archon-messages" class="archon-messages" phx-hook="ScrollBottom">
        <.empty_state :if={@messages == []} />
        <.chat_bubble :for={msg <- @messages} role={msg.role} content={msg[:content] || format_structured(msg)} />
        <.typing_indicator :if={@loading} />
      </div>
      <div class="archon-input-area">
        <div id="archon-input-stable" phx-update="ignore">
          <form id="archon-chat-form" phx-submit="archon_send" phx-hook="ClearFormOnSubmit" class="flex gap-2">
            <input type="text" name="content" autocomplete="off" placeholder="Command Archon..." class="archon-input" />
            <button type="submit" class="archon-send-btn">Transmit</button>
          </form>
        </div>
      </div>
    </div>
    """
  end

  defp empty_state(assigns) do
    ~H"""
    <div class="flex flex-col items-center justify-center h-full opacity-40">
      <svg class="w-16 h-16 text-brand/30 mb-4" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="0.5">
        <circle cx="12" cy="12" r="10" />
        <path d="M12 2L2 7l10 5 10-5-10-5z" />
        <path d="M2 17l10 5 10-5" />
        <path d="M2 12l10 5 10-5" />
      </svg>
      <p class="text-xs text-muted font-mono uppercase tracking-widest">Awaiting command</p>
    </div>
    """
  end

  attr :role, :atom, required: true
  attr :content, :string, required: true

  defp chat_bubble(assigns) do
    assigns = Phoenix.Component.assign(assigns, :rendered, render(assigns.content))

    ~H"""
    <div class={["archon-msg", role_class(@role)]}>
      <div class={["archon-bubble", bubble_class(@role)]}>
        <div class="archon-prose">{@rendered}</div>
      </div>
      <div class={["archon-meta", meta_class(@role)]}>{role_label(@role)}</div>
    </div>
    """
  end

  defp typing_indicator(assigns) do
    ~H"""
    <div class="archon-msg">
      <div class="archon-bubble archon-bubble-assistant">
        <div class="flex items-center gap-2 text-xs text-muted">
          <div class="flex gap-1">
            <div class="archon-typing-dot" style="animation-delay: 0ms" />
            <div class="archon-typing-dot" style="animation-delay: 150ms" />
            <div class="archon-typing-dot" style="animation-delay: 300ms" />
          </div>
          <span class="font-mono text-[10px] uppercase tracking-wider">processing</span>
        </div>
      </div>
    </div>
    """
  end

  defp role_class(:user), do: "archon-msg-user"
  defp role_class(:system), do: "archon-msg-system"
  defp role_class(_), do: ""

  defp bubble_class(:user), do: "archon-bubble-user"
  defp bubble_class(:system), do: "archon-bubble-system"
  defp bubble_class(_), do: "archon-bubble-assistant"

  defp meta_class(:user), do: "archon-meta-user"
  defp meta_class(:system), do: "archon-meta-system"
  defp meta_class(_), do: "archon-meta-assistant"

  defp role_label(:system), do: "alert"
  defp role_label(:user), do: "architect"
  defp role_label(_), do: "archon"

  defp format_structured(%{type: type, data: data}) when is_list(data) do
    "[#{type}] #{length(data)} results"
  end

  defp format_structured(%{type: type, data: data}) when is_map(data) do
    "[#{type}] #{inspect(data, pretty: true, limit: 5)}"
  end

  defp format_structured(%{data: data}) when is_binary(data), do: data
  defp format_structured(_), do: ""

end
