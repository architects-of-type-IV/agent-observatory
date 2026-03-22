defmodule Ichor.Settings.Types.LocationType do
  @moduledoc """
  Ash enum type for project location kind.

  - `:local`  -- local filesystem folder
  - `:remote` -- remote server folder (SSH)
  """

  use Ash.Type.Enum, values: [:local, :remote]
end
