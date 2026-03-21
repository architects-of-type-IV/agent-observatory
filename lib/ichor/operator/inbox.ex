defmodule Ichor.Operator.Inbox do
  @moduledoc """
  Single write path for operator inbox notifications.

  Writes structured JSON notifications to `~/.claude/inbox/` so the operator
  (human or AI coordinator) can discover them on next check-in. All callers
  use this module rather than writing files directly, ensuring a consistent
  canonical schema across notification types.

  ## Canonical schema

  Every notification is an atom-keyed map:

      %{
        type: atom,
        payload: map,
        timestamp: DateTime.t(),
        id: String.t()
      }

  ## Filename convention

  Files are named `{type}_{short_context}_{timestamp_ms}.json` where
  `short_context` is a caller-supplied string (team name, session short ID,
  etc.) that makes the file easy to identify in a directory listing.
  """

  require Logger

  @inbox_dir Path.expand("~/.claude/inbox")

  @type notification :: %{
          type: atom(),
          payload: map(),
          timestamp: DateTime.t(),
          id: String.t()
        }

  @doc """
  Writes a notification to `~/.claude/inbox/`.

  `type` is the notification type atom (e.g. `:agent_crash`, `:team_watchdog`).
  `payload` is caller-supplied context data.

  An optional `:context` key in `payload` is used to build the filename
  (short team name, session ID fragment, etc.). Falls back to the type name
  when absent.

  Returns `{:ok, path}` on success or `{:error, reason}` on failure.
  """
  @spec write(atom(), map()) :: {:ok, String.t()} | {:error, term()}
  def write(type, payload) when is_atom(type) and is_map(payload) do
    notification = %{
      type: type,
      payload: payload,
      timestamp: DateTime.utc_now(),
      id: generate_id()
    }

    short_context = Map.get(payload, :context, Atom.to_string(type))
    timestamp_ms = System.system_time(:millisecond)
    filename = "#{type}_#{short_context}_#{timestamp_ms}.json"
    path = Path.join(@inbox_dir, filename)

    with :ok <- File.mkdir_p(@inbox_dir),
         {:ok, json} <- Jason.encode(notification, pretty: true),
         :ok <- File.write(path, json) do
      {:ok, path}
    else
      {:error, reason} ->
        Logger.error("Operator.Inbox: Failed to write notification #{type}: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end
end
