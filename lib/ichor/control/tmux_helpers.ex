defmodule Ichor.Control.TmuxHelpers do
  @moduledoc """
  Shared helpers for tmux-based agent spawning.
  Used by lifecycle, MES, and Genesis tmux-backed runtime flows.
  """

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")

  @spec tmux_args() :: [String.t()]
  def tmux_args do
    case File.exists?(@ichor_socket) do
      true -> ["-S", @ichor_socket]
      false -> ["-L", "obs"]
    end
  end

  @spec capability_to_role(String.t()) :: atom()
  def capability_to_role("coordinator"), do: :coordinator
  def capability_to_role("lead"), do: :lead
  def capability_to_role(_), do: :worker

  @spec capabilities_for(String.t()) :: [atom()]
  def capabilities_for("coordinator"), do: [:read, :write, :spawn, :assign, :escalate, :kill]
  def capabilities_for("lead"), do: [:read, :write, :spawn, :assign, :escalate]
  def capabilities_for("scout"), do: [:read]
  def capabilities_for(_), do: [:read, :write]

  @spec add_permission_args([String.t()], String.t()) :: [String.t()]
  def add_permission_args(args, cap) when cap in ["builder", "lead", "coordinator"],
    do: args ++ ["--dangerously-skip-permissions"]

  def add_permission_args(args, "scout"),
    do:
      args ++
        [
          "--allowedTools",
          "Read",
          "Glob",
          "Grep",
          "WebSearch",
          "WebFetch",
          "Bash",
          "mcp__ichor__check_inbox",
          "mcp__ichor__send_message",
          "mcp__ichor__acknowledge_message"
        ]

  def add_permission_args(args, _), do: args
end
