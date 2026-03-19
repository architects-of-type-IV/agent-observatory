defmodule Ichor.Signals.Catalog do
  @moduledoc """
  Declarative catalog of every signal in the ICHOR nervous system.
  Source of truth for signal validation, the /signals page, and Archon Watchdog.

  Add new signals here. If it's not in the catalog, `Signals.emit/2` raises.
  """

  @type signal_def :: %{
          category: atom(),
          keys: [atom()],
          dynamic: boolean(),
          doc: String.t()
        }

  alias Ichor.Signals.Catalog.CoreDefs
  alias Ichor.Signals.Catalog.GatewayAgentDefs
  alias Ichor.Signals.Catalog.GenesisDagDefs
  alias Ichor.Signals.Catalog.MesDefs
  alias Ichor.Signals.Catalog.TeamMonitoringDefs

  @signals CoreDefs.definitions()
           |> Map.merge(GatewayAgentDefs.definitions())
           |> Map.merge(TeamMonitoringDefs.definitions())
           |> Map.merge(MesDefs.definitions())
           |> Map.merge(GenesisDagDefs.definitions())

  @catalog Map.new(@signals, fn {k, v} -> {k, Map.put_new(v, :dynamic, false)} end)
  @categories @catalog |> Map.values() |> Enum.map(& &1.category) |> Enum.uniq() |> Enum.sort()
  @static_signals @catalog |> Enum.reject(fn {_, v} -> v.dynamic end) |> Enum.map(&elem(&1, 0))

  @spec lookup(atom()) :: signal_def() | nil
  def lookup(name), do: Map.get(@catalog, name)

  @spec lookup!(atom()) :: signal_def()
  def lookup!(name) do
    Map.get(@catalog, name) || derive(name)
  end

  @doc "Derive a signal definition from its name prefix. Allows signals to work without catalog entries."
  @spec derive(atom()) :: signal_def()
  def derive(name) do
    category =
      name
      |> Atom.to_string()
      |> String.split("_", parts: 2)
      |> hd()
      |> String.to_existing_atom()

    %{category: category, keys: [], dynamic: false, doc: "auto-derived"}
  rescue
    ArgumentError -> %{category: :uncategorized, keys: [], dynamic: false, doc: "auto-derived"}
  end

  @spec valid_category?(atom()) :: boolean()
  def valid_category?(cat), do: cat in @categories

  @spec categories() :: [atom()]
  def categories, do: @categories

  @spec all() :: %{atom() => signal_def()}
  def all, do: @catalog

  @spec by_category(atom()) :: [{atom(), signal_def()}]
  def by_category(cat), do: Enum.filter(@catalog, fn {_, v} -> v.category == cat end)

  @spec static_signals() :: [atom()]
  def static_signals, do: @static_signals

  @spec dynamic_signals() :: [{atom(), signal_def()}]
  def dynamic_signals, do: Enum.filter(@catalog, fn {_, v} -> v.dynamic end)
end
