defmodule Ichor.Activity.Task do
  @moduledoc """
  A task derived from TaskCreate/TaskUpdate hook events.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource,
    domain: Ichor.Observability,
    simple_notifiers: [Ichor.Signals.FromAsh]

  attributes do
    attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:subject, :string, public?: true)
    attribute(:description, :string, public?: true)
    attribute(:status, :string, default: "pending", public?: true)
    attribute(:owner, :string, public?: true)
    attribute(:active_form, :string, public?: true)
    attribute(:session_id, :string, public?: true)
    attribute(:created_at, :utc_datetime_usec, public?: true)
  end

  actions do
    read :current do
      prepare({Ichor.Activity.Preparations.LoadTasks, []})
    end
  end

  code_interface do
    define(:current)
  end
end
