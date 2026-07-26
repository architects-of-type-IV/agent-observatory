defmodule HostRegistry.Host do
  @moduledoc """
  One host in the fleet: a BEAM node that can run work.

  ## Status

    * `:connected` — the node is reachable from here right now
    * `:registered` — registered ahead of time but not currently reachable
    * `:disconnected` — was connected and has since gone away

  `:registered` and `:disconnected` are deliberately distinct. Both mean
  "not reachable", but one is a host that has not arrived yet and the other is a
  host that left — which is the difference between waiting and investigating.
  """

  @enforce_keys [:node, :hostname, :status]
  defstruct [:node, :hostname, :status, :connected_at, capabilities: [], metadata: %{}]

  @type status :: :connected | :registered | :disconnected

  @type t :: %__MODULE__{
          node: node(),
          hostname: String.t(),
          status: status(),
          connected_at: DateTime.t() | nil,
          capabilities: [atom()],
          metadata: map()
        }

  @doc "Build an entry for a node at a given status."
  @spec new(node(), status(), keyword()) :: t()
  def new(node, status, opts \\ []) do
    %__MODULE__{
      node: node,
      hostname: hostname(node),
      status: status,
      connected_at: if(status == :connected, do: DateTime.utc_now()),
      capabilities: Keyword.get(opts, :capabilities, []),
      metadata: Keyword.get(opts, :metadata, %{})
    }
  end

  @doc """
  The host part of a node name.

      iex> HostRegistry.Host.hostname(:"worker@box-1")
      "box-1"

  A node with no `@` — `:nonode@nohost` aside — yields the name itself.

      iex> HostRegistry.Host.hostname(:standalone)
      "standalone"
  """
  @spec hostname(node()) :: String.t()
  def hostname(node) do
    node
    |> Atom.to_string()
    |> String.split("@")
    |> List.last()
  end
end
