defmodule Observatory.Repo do
  use Ecto.Repo,
    otp_app: :observatory,
    adapter: Ecto.Adapters.SQLite3

  def installed_extensions do
    []
  end
end
