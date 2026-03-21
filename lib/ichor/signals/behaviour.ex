defmodule Ichor.Signals.Behaviour do
  @moduledoc false

  @callback emit(atom(), map()) :: :ok
  @callback emit(atom(), String.t(), map()) :: :ok
  @callback subscribe(atom()) :: :ok | {:error, term()}
  @callback subscribe(atom(), String.t()) :: :ok | {:error, term()}
  @callback unsubscribe(atom()) :: :ok
  @callback unsubscribe(atom(), String.t()) :: :ok
  @callback category_topic(atom()) :: String.t()
  @callback categories() :: [atom()]
end
