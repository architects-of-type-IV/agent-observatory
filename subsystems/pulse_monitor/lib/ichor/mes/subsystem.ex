defmodule Ichor.Mes.Subsystem do
  @moduledoc "Stub behaviour for standalone compilation. Replaced by host VM at runtime."

  @callback info() :: struct()
  @callback start() :: :ok | {:error, term()}
  @callback handle_signal(map()) :: :ok
  @callback stop() :: :ok
end
