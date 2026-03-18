defmodule Ichor.Repo do
  use Ecto.Repo,
    otp_app: :ichor_data,
    adapter: Ecto.Adapters.SQLite3

  def installed_extensions, do: []
end
