defmodule Ichor.Repo do
  @moduledoc "Ecto repository for the Ichor PostgreSQL database."

  use Ecto.Repo,
    otp_app: :ichor,
    adapter: Ecto.Adapters.Postgres

  @doc false
  @spec installed_extensions() :: [String.t()]
  def installed_extensions, do: ["uuid-ossp", "citext"]
end
