defmodule Ichor.Fleet.Lifecycle.AgentLaunch do
  @moduledoc """
  Lifecycle operations for launching and stopping individual agents.
  """

  require Logger

  alias Ichor.Fleet.HostRegistry
  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.Lifecycle.Cleanup
  alias Ichor.Fleet.Lifecycle.Registration
  alias Ichor.Fleet.Lifecycle.TmuxLauncher
  alias Ichor.Fleet.Lifecycle.TmuxScript

  @agents_dir Path.expand("~/.ichor/agents")

  @type launch_opts :: %{
          optional(:name) => String.t(),
          optional(:capability) => String.t(),
          optional(:model) => String.t(),
          optional(:task) => map(),
          optional(:cwd) => String.t(),
          optional(:team_name) => String.t(),
          optional(:extra_instructions) => String.t(),
          optional(:parent_id) => String.t(),
          optional(:host) => node()
        }

  @standalone_session "ichor-fleet"
  @counter_key :ichor_spawn_counter

  @doc "Initialize the atomic spawn counter. Called once at application startup."
  @spec init_counter() :: :ok
  def init_counter do
    ref = :atomics.new(1, signed: false)
    :persistent_term.put(@counter_key, ref)
    :ok
  end

  @doc "Spawn an agent locally or on a remote node if `host` is specified in opts."
  @spec spawn(launch_opts()) :: {:ok, map()} | {:error, term()}
  def spawn(%{host: target} = opts) when not is_nil(target) do
    case HostRegistry.available?(target) do
      true -> spawn_remote(target, opts)
      false -> {:error, {:host_unavailable, target}}
    end
  end

  def spawn(opts), do: spawn_local(opts)

  @doc "Spawn an agent on the local node: validate, write scripts, create tmux window, register."
  @spec spawn_local(launch_opts()) :: {:ok, map()} | {:error, term()}
  def spawn_local(opts) do
    spec = build_spec(opts)

    with :ok <- validate_cwd(spec.cwd),
         :ok <- validate_no_window_conflict(spec.session, spec.window_name),
         {:ok, %{script_path: script_path}} <-
           TmuxScript.write_agent_files(
             @agents_dir,
             spec.window_name,
             spec.prompt || "",
             spec.model || "sonnet",
             spec.capability || "builder"
           ),
         :ok <- launch_window(spec, script_path) do
      Registration.register(spec, "#{spec.session}:#{spec.window_name}")
    end
  end

  @doc "Stop an agent process and clean up its backend."
  @spec stop(String.t()) :: :ok | {:error, term()}
  def stop(agent_id), do: Cleanup.stop_agent(agent_id)

  defp spawn_remote(node, opts) do
    Logger.info("[Lifecycle.AgentLaunch] Spawning on remote node #{node}")

    case :rpc.call(node, __MODULE__, :spawn_local, [opts]) do
      {:badrpc, reason} -> {:error, {:remote_spawn_failed, node, reason}}
      {:ok, result} -> {:ok, Map.put(result, :node, node)}
      {:error, _} = error -> error
    end
  end

  defp build_spec(opts) do
    name = opts[:name] || opts[:capability] || "agent"
    cwd = opts[:cwd] || File.cwd!()
    window_name = "#{name}-#{next_counter()}"
    session = opts[:team_name] || @standalone_session
    prompt = get_in(opts, [:task, "description"]) || get_in(opts, [:task, :description]) || ""

    AgentSpec.new(%{
      name: name,
      window_name: window_name,
      agent_id: window_name,
      capability: opts[:capability] || "builder",
      model: opts[:model] || "sonnet",
      cwd: cwd,
      team_name: opts[:team_name],
      session: session,
      prompt: prompt,
      metadata: %{parent_id: opts[:parent_id]}
    })
  end

  defp next_counter do
    ref = :persistent_term.get(@counter_key)
    :atomics.add_get(ref, 1, 1)
  end

  defp launch_window(spec, script_path) do
    if TmuxLauncher.available?(spec.session) do
      TmuxLauncher.create_window(spec.session, spec.window_name, spec.cwd, script_path)
    else
      TmuxLauncher.create_session(spec.session, spec.cwd, spec.window_name, script_path)
    end
  end

  defp validate_no_window_conflict(session, window_name) do
    case TmuxLauncher.available?("#{session}:#{window_name}") do
      true -> {:error, {:window_exists, "#{session}:#{window_name}"}}
      false -> :ok
    end
  end

  defp validate_cwd(cwd) do
    if File.dir?(cwd), do: :ok, else: {:error, {:cwd_not_found, cwd}}
  end
end
