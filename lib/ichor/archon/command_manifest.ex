defmodule Ichor.Archon.CommandManifest do
  @moduledoc """
  Single source of truth for Archon command metadata.
  """

  @quick_actions [
    %{key: "1", cmd: "manager", label: "Manager", icon: "brain", desc: "System snapshot"},
    %{key: "2", cmd: "attention", label: "Attention", icon: "pulse", desc: "Open issues"},
    %{key: "3", cmd: "agents", label: "Agents", icon: "grid", desc: "List fleet"},
    %{key: "4", cmd: "teams", label: "Teams", icon: "layers", desc: "Active teams"},
    %{key: "5", cmd: "inbox", label: "Inbox", icon: "mail", desc: "Messages"},
    %{key: "6", cmd: "sessions", label: "Sessions", icon: "terminal", desc: "Tmux"},
    %{key: "7", cmd: "recall", label: "Recall", icon: "search", desc: "Search memory"}
  ]

  @reference_commands [
    {"manager", "Summarize the system from signals"},
    {"attention", "Show issues needing intervention"},
    {"agents", "List all agents in the fleet"},
    {"teams", "List all active teams"},
    {"status <agent>", "Check an agent's status"},
    {"msg <target> <text>", "Send a message to an agent or team"},
    {"inbox", "Show recent messages"},
    {"health", "System health check"},
    {"sessions", "List tmux sessions"},
    {"remember <text>", "Persist an observation to memory"},
    {"recall <query>", "Search knowledge graph"},
    {"query <question>", "Natural language memory query"}
  ]

  @usage_groups [
    {"Observation",
     "/agents /teams /status <id> /events <id> [limit] /tasks [team] /inbox /health /sessions"},
    {"Manager", "/manager /attention"},
    {"Control", "/spawn <prompt> /stop <id> /pause <id> [reason] /resume <id> /sweep"},
    {"Messaging", "/msg <target> <text>"},
    {"MES", "/mes /projects [status] /operator-inbox /cleanup-mes"},
    {"Memory", "/remember <text> /recall <query> /query <question>"}
  ]

  @spec quick_actions() :: [map()]
  def quick_actions, do: @quick_actions

  @spec reference_commands() :: [{String.t(), String.t()}]
  def reference_commands, do: @reference_commands

  @spec unknown_command_help(String.t()) :: String.t()
  def unknown_command_help(command) do
    lines =
      Enum.map(@usage_groups, fn {label, usage} ->
        padded = String.pad_trailing(label <> ":", 13)
        "#{padded} #{usage}"
      end)

    Enum.join(["Unknown command: #{command}" | lines], "\n")
  end
end
