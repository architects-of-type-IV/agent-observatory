defmodule Ichor.Fleet.Session do
  @moduledoc """
  A running AI agent session.

  A session is a live execution of a Claude, Gemini, Codex, or other AI
  provider process, typically running in a tmux pane. The Workshop blueprint
  defines what an agent should be; the Fleet session is the running instance.

  State machine: pending -> active -> paused -> completed | failed | crashed
  """

  use Ash.Resource, domain: Ichor.Fleet

  alias Ichor.Fleet.Registry
  alias Ichor.Fleet.SessionProcess

  attributes do
    attribute(:id, :string, primary_key?: true, allow_nil?: false, public?: true)
    attribute(:name, :string, public?: true)

    attribute :provider, :atom do
      constraints(one_of: [:claude, :gemini, :codex, :shell, :system, :tmux])
      public?(true)
    end

    attribute :status, :atom do
      constraints(one_of: [:pending, :active, :paused, :completed, :failed, :crashed])
      default(:pending)
      public?(true)
    end

    attribute(:role, :atom, public?: true)
    attribute(:team, :string, public?: true)
    attribute(:parent_session_id, :string, public?: true)
    attribute(:model, :string, public?: true)
    attribute(:cwd, :string, public?: true)
    attribute(:channels, :map, default: %{}, public?: true)
    attribute(:context, :map, default: %{}, public?: true)
    attribute(:tags, {:array, :string}, default: [], public?: true)
    attribute(:started_at, :utc_datetime_usec, public?: true)
    attribute(:last_event_at, :utc_datetime_usec, public?: true)
  end

  actions do
    read :list do
      prepare({Ichor.Fleet.Preparations.LoadSessions, []})
    end

    read :active do
      prepare({Ichor.Fleet.Preparations.LoadSessions, []})
      filter(expr(status in [:active, :paused, :pending]))
    end

    action :spawn, :map do
      argument(:name, :string, allow_nil?: false)
      argument(:provider, :atom, allow_nil?: false, default: :claude)
      argument(:role, :atom, allow_nil?: false, default: :worker)
      argument(:team, :string, allow_nil?: false, default: "")
      argument(:prompt, :string, allow_nil?: false, default: "")

      run(fn input, _context ->
        SessionProcess.start(input.arguments)
      end)
    end

    action :stop, :map do
      argument(:session, :string, allow_nil?: false)

      run(fn input, _context ->
        Registry.terminate(input.arguments.session)
      end)
    end
  end
end
