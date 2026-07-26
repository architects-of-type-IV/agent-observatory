defmodule Signals.Registry do
  @moduledoc """
  Locates the accumulator for a `{signal, key}`, starting it if needed.

  Accumulators are spawned on demand — the set of keys is not known ahead of
  time, since it is whatever agents and teams happen to exist. A signal with no
  traffic costs nothing.
  """

  @registry Signals.ProcessRegistry
  @supervisor Signals.AccumulatorSupervisor

  @doc false
  def child_spec(_opts) do
    %{
      id: __MODULE__,
      start: {__MODULE__, :start_link, []},
      type: :supervisor
    }
  end

  @doc false
  def start_link do
    Supervisor.start_link(
      [
        {Registry, keys: :unique, name: @registry},
        {DynamicSupervisor, name: @supervisor, strategy: :one_for_one}
      ],
      strategy: :one_for_one,
      name: __MODULE__.Supervisor
    )
  end

  @doc "The `:via` tuple naming one accumulator."
  @spec via(module(), String.t() | nil) :: {:via, Registry, {atom(), {module(), term()}}}
  def via(signal, key), do: {:via, Registry, {@registry, {signal, key}}}

  @doc """
  The accumulator for `{signal, key}`, started if it is not already running.

  Two events for the same key arriving together race here; `:already_started`
  resolves to the winner rather than an error, so neither is dropped.
  """
  @spec ensure(module(), String.t() | nil) :: {:ok, pid()} | {:error, term()}
  def ensure(signal, key) do
    case whereis(signal, key) do
      nil -> start(signal, key)
      pid -> {:ok, pid}
    end
  end

  @doc "The accumulator for `{signal, key}`, or `nil`."
  @spec whereis(module(), String.t() | nil) :: pid() | nil
  def whereis(signal, key) do
    case Registry.lookup(@registry, {signal, key}) do
      [{pid, _}] -> pid
      [] -> nil
    end
  end

  @doc "Every running accumulator as `{signal, key, pid}`."
  @spec list() :: [{module(), term(), pid()}]
  def list do
    Registry.select(@registry, [{{:"$1", :"$2", :_}, [], [{{:"$1", :"$2"}}]}])
    |> Enum.map(fn {{signal, key}, pid} -> {signal, key, pid} end)
  end

  @doc "Stop every accumulator. Test helper."
  @spec stop_all() :: :ok
  def stop_all do
    for {_signal, _key, pid} <- list() do
      DynamicSupervisor.terminate_child(@supervisor, pid)
    end

    :ok
  end

  defp start(signal, key) do
    case DynamicSupervisor.start_child(
           @supervisor,
           {Signals.Accumulator, signal: signal, key: key}
         ) do
      {:ok, pid} -> {:ok, pid}
      {:error, {:already_started, pid}} -> {:ok, pid}
      {:error, reason} -> {:error, reason}
    end
  end
end
