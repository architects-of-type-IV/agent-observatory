defmodule Ichor.TestSupport.ArchonStubChainBuilder do
  def build do
    {:ok, %{messages: [:system_seed], last_message: nil}}
  end
end
