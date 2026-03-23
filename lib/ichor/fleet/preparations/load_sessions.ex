defmodule Ichor.Fleet.Preparations.LoadSessions do
  @moduledoc "Loads sessions from Fleet Registry."

  use Ash.Resource.Preparation

  @impl true
  def prepare(query, _opts, _context) do
    sessions =
      Registry.select(Ichor.Fleet.Registry, [{{:"$1", :"$2", :"$3"}, [], [{{:"$1", :"$3"}}]}])
      |> Enum.map(fn {id, meta} -> to_session(id, meta) end)

    Ash.DataLayer.Simple.set_data(query, sessions)
  end

  defp to_session(id, meta) do
    struct!(Ichor.Fleet.Session, %{
      id: id,
      name: meta[:name] || id,
      provider: meta[:provider] || :claude,
      role: meta[:role],
      team: meta[:team],
      status: meta[:status] || :active,
      model: meta[:model],
      cwd: meta[:cwd],
      channels: meta[:channels] || %{},
      context: meta[:context] || %{},
      tags: meta[:tags] || [],
      started_at: meta[:started_at],
      last_event_at: meta[:last_event_at]
    })
  end
end
