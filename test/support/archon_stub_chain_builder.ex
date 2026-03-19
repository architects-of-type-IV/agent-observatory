defmodule Ichor.TestSupport.ArchonStubChainBuilder do
  @moduledoc false

  def build do
    {:ok, %{messages: [:system_seed], last_message: nil}}
  end
end
