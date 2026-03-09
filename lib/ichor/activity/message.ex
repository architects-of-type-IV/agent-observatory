defmodule Ichor.Activity.Message do
  @moduledoc """
  An inter-agent message derived from SendMessage hook events.
  Uses Ash.DataLayer.Simple -- data is loaded by preparations, not persisted.
  """

  use Ash.Resource, domain: Ichor.Activity


  attributes do
    attribute :id, :string, primary_key?: true, allow_nil?: false, public?: true
    attribute :sender_session, :string, public?: true
    attribute :sender_app, :string, public?: true
    attribute :type, :string, default: "message", public?: true
    attribute :recipient, :string, public?: true
    attribute :content, :string, public?: true
    attribute :summary, :string, public?: true
    attribute :timestamp, :utc_datetime_usec, public?: true
  end

  actions do
    read :recent do
      prepare {Ichor.Activity.Preparations.LoadMessages, []}
    end
  end

  code_interface do
    define :recent
  end
end
