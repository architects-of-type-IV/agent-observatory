defmodule Ichor.Infrastructure.TmuxOperations do
  @moduledoc """
  Ash resource wrapping the Tmux module's public API as generic actions.

  Provides a domain-level, policy-ready, code_interface-callable surface for
  all tmux operations. The underlying Tmux module is not modified.
  """

  use Ash.Resource, domain: Ichor.Infrastructure

  alias Ichor.Infrastructure.Tmux

  code_interface do
    define(:list_sessions)
    define(:list_panes)
    define(:list_windows, args: [:session])
    define(:list_sessions_with_windows)
    define(:capture_pane, args: [:target])
    define(:send_keys, args: [:target, :keys])
    define(:deliver, args: [:session, :payload])
    define(:available, args: [:target])
  end

  actions do
    action :list_sessions, {:array, :string} do
      description("List all active tmux sessions across all known servers.")

      run(fn _input, _context ->
        {:ok, Tmux.list_sessions()}
      end)
    end

    action :list_panes, {:array, :map} do
      description("List all panes across all known servers with pane_id, session, and title.")

      run(fn _input, _context ->
        {:ok, Tmux.list_panes()}
      end)
    end

    action :list_windows, {:array, :map} do
      description("List all windows in a session as name/target pairs.")

      argument(:session, :string, allow_nil?: false)

      run(fn input, _context ->
        {:ok, Tmux.list_windows(input.arguments.session)}
      end)
    end

    action :list_sessions_with_windows, {:array, :map} do
      description("List all sessions with their windows.")

      run(fn _input, _context ->
        {:ok, Tmux.list_sessions_with_windows()}
      end)
    end

    action :capture_pane, :string do
      description("Capture current output from a tmux pane.")

      argument(:target, :string, allow_nil?: false)
      argument(:lines, :integer, allow_nil?: false, default: 50)
      argument(:ansi, :boolean, allow_nil?: false, default: false)

      run(fn input, _context ->
        Tmux.capture_pane(input.arguments.target, ansi: input.arguments.ansi)
      end)
    end

    action :send_keys, :boolean do
      description("Send keystrokes to a tmux pane.")

      argument(:target, :string, allow_nil?: false)
      argument(:keys, :string, allow_nil?: false)

      run(fn input, _context ->
        case Tmux.run_command(["send-keys", "-t", input.arguments.target, input.arguments.keys]) do
          {:ok, _} -> {:ok, true}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :deliver, :boolean do
      description("Deliver a message payload to a tmux session by name.")

      argument(:session, :string, allow_nil?: false)
      argument(:payload, :map, allow_nil?: false)

      run(fn input, _context ->
        case Tmux.deliver(input.arguments.session, input.arguments.payload) do
          :ok -> {:ok, true}
          {:error, reason} -> {:error, reason}
        end
      end)
    end

    action :available, :boolean do
      description("Check whether a tmux session or pane target is available.")

      argument(:target, :string, allow_nil?: false)

      run(fn input, _context ->
        {:ok, Tmux.available?(input.arguments.target)}
      end)
    end
  end
end
