defmodule Ichor.Mes.Subsystem.Info do
  @moduledoc """
  The self-describing manifest every subsystem returns from `info/0`.

  This struct is the plugin contract. The runtime reads it to auto-wire
  PubSub, register signals, and display the subsystem in the dashboard.
  Every subsystem returns the same shape -- that uniformity is what makes
  auto-discovery work.

  ## Fields

  | Field | Purpose |
  |-------|---------|
  | `name` | Human-readable name (e.g. "Correlator") |
  | `module` | The implementing module (e.g. `Ichor.Subsystems.Correlator`) |
  | `description` | One sentence: what it does |
  | `topic` | Unique PubSub topic (e.g. `"subsystem:correlator"`). This is the subsystem's address. |
  | `version` | SemVer string |
  | `signals_emitted` | Atoms this subsystem emits (registered in Catalog on load) |
  | `signals_subscribed` | Atoms or `:all` this subsystem listens to |
  | `features` | List of capability descriptions (what it can do) |
  | `use_cases` | List of concrete scenarios (when you'd use it) |
  | `dependencies` | Ichor modules it requires (e.g. `[Ichor.Signals, :ets]`) |
  | `architecture` | Brief description of internal structure |
  """

  @enforce_keys [:name, :module, :description, :topic, :version]
  defstruct [
    :name,
    :module,
    :description,
    :topic,
    :version,
    :architecture,
    signals_emitted: [],
    signals_subscribed: [],
    features: [],
    use_cases: [],
    dependencies: []
  ]

  @type t :: %__MODULE__{
          name: String.t(),
          module: module(),
          description: String.t(),
          topic: String.t(),
          version: String.t(),
          architecture: String.t() | nil,
          signals_emitted: [atom()],
          signals_subscribed: [atom() | :all],
          features: [String.t()],
          use_cases: [String.t()],
          dependencies: [module() | atom()]
        }
end
