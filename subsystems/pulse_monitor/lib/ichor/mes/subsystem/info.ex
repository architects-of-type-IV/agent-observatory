defmodule Ichor.Mes.Subsystem.Info do
  @moduledoc "Stub struct for standalone compilation. Replaced by host VM at runtime."

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
end
