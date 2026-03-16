defmodule Ichor.Fleet.TmuxHelpers do
  @moduledoc """
  Shared helpers for tmux-based agent spawning.
  Used by AgentSpawner, MES TeamSpawner, and Genesis ModeRunner.
  """

  alias Ichor.Fleet.FleetSupervisor

  @ichor_socket Path.expand("~/.ichor/tmux/obs.sock")

  @spec tmux_args() :: [String.t()]
  def tmux_args do
    case File.exists?(@ichor_socket) do
      true -> ["-S", @ichor_socket]
      false -> ["-L", "obs"]
    end
  end

  @spec ensure_team(String.t()) :: :ok | {:error, term()}
  def ensure_team(name) do
    case FleetSupervisor.create_team(name: name) do
      {:ok, _pid} -> :ok
      {:error, :already_exists} -> :ok
      {:error, {:already_started, _pid}} -> :ok
      {:error, reason} -> {:error, reason}
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
    do: args ++ ["--allowedTools", "Read", "Glob", "Grep", "WebSearch", "WebFetch", "Bash"]

  def add_permission_args(args, _), do: args
end
