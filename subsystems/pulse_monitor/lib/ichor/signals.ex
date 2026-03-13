defmodule Ichor.Signals do
  @moduledoc "Stub for standalone compilation. Host VM provides real implementation."

  def emit(_name, _data), do: :ok
  def subscribe(_category), do: :ok
end

defmodule Ichor.Signals.Catalog do
  @moduledoc false
  def categories, do: []
end

defmodule Ichor.Signals.Topics do
  @moduledoc false
  def category(cat), do: "signal:#{cat}"
end

defmodule Ichor.Signals.Message do
  @moduledoc false
  defstruct [
    :name,
    :kind,
    :domain,
    :data,
    :timestamp,
    :source,
    :correlation_id,
    :causation_id,
    :meta
  ]
end
