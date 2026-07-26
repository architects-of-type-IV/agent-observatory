defmodule AgentPromptProtocol.Config do
  @moduledoc """
  Runtime configuration for `AgentPromptProtocol`.

  Every value has a default, so nothing needs configuring to use the library.

      config :agent_prompt_protocol,
        send_function: "send_message",
        inbox_function: "check_inbox",
        operator_id: "operator",
        operator_description: "final deliverables to the dashboard",
        operator_capabilities: ["coordinator"],
        id_kinds: [:mes, :pipeline, :planning]

  ## Why the tool names are configurable

  The protocol text names the exact tools the agent must call. If your messaging
  tools are called something else, the generated rules would instruct the agent
  to call functions that do not exist — which is the single most effective way
  to make a prompt fail silently.
  """

  @defaults %{
    send_function: "send_message",
    inbox_function: "check_inbox",
    operator_id: "operator",
    operator_description: "final deliverables to the dashboard",
    operator_capabilities: ["coordinator"],
    id_kinds: [:mes, :pipeline, :planning]
  }

  @doc "Name of the tool an agent calls to send a message."
  @spec send_function() :: String.t()
  def send_function, do: get(:send_function)

  @doc "Name of the tool an agent calls to poll its inbox."
  @spec inbox_function() :: String.t()
  def inbox_function, do: get(:inbox_function)

  @doc "Session id of the human-facing operator endpoint."
  @spec operator_id() :: String.t()
  def operator_id, do: get(:operator_id)

  @doc "How the operator contact is described in an ALLOWED CONTACTS block."
  @spec operator_description() :: String.t()
  def operator_description, do: get(:operator_description)

  @doc "Capabilities that are granted the operator contact."
  @spec operator_capabilities() :: [String.t()]
  def operator_capabilities, do: get(:operator_capabilities)

  @doc "Recognised `AgentPromptProtocol.AgentId` kinds."
  @spec id_kinds() :: [atom()]
  def id_kinds, do: get(:id_kinds)

  defp get(key), do: Application.get_env(:agent_prompt_protocol, key, Map.fetch!(@defaults, key))
end
