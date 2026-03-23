defmodule Ichor.Repo do
  @moduledoc "Ecto repository for the Ichor PostgreSQL database."

  use AshPostgres.Repo, otp_app: :ichor

  @doc false
  def installed_extensions, do: ["ash-functions", "uuid-ossp", "citext"]

  @doc false
  def min_pg_version, do: %Version{major: 16, minor: 0, patch: 0}
end
