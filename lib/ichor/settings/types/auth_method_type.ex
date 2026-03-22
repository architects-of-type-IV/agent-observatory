defmodule Ichor.Settings.Types.AuthMethodType do
  @moduledoc """
  Ash enum type for remote connection authentication method.

  - `:ssh_key`  -- authenticate via SSH key
  - `:password` -- authenticate via password
  """

  use Ash.Type.Enum, values: [:ssh_key, :password]
end
