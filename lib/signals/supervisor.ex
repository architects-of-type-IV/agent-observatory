defmodule Signals.Supervisor do
  @moduledoc """
  Starts the runtime: registry, and the configured store and sink when they are
  processes.

  Order matters. The registry must exist before the router can place an
  accumulator, and the store must exist before an accumulator restores from it,
  so this is `:rest_for_one` — a store restart takes the accumulators with it
  rather than leaving them reading from a table that no longer exists.

      children = [Signals.Supervisor]
  """

  use Supervisor

  alias Signals.Config

  @spec start_link(keyword()) :: Supervisor.on_start()
  def start_link(opts \\ []), do: Supervisor.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    children =
      [Config.store(), Config.sink()]
      |> Enum.filter(&process?/1)
      |> Enum.uniq()
      |> Kernel.++([Signals.Registry])

    Supervisor.init(children, strategy: :rest_for_one)
  end

  # A store or sink may be a plain module with no process behind it.
  defp process?(module) do
    Code.ensure_loaded?(module) and function_exported?(module, :child_spec, 1)
  end
end
