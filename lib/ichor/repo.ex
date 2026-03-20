defmodule Ichor.Repo do
  @moduledoc "Ecto repository for the Ichor SQLite database."

  use Ecto.Repo,
    otp_app: :ichor,
    adapter: Ecto.Adapters.SQLite3

  @doc false
  @spec installed_extensions() :: []
  def installed_extensions, do: []
end
