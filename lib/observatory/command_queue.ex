defmodule Observatory.CommandQueue do
  @moduledoc """
  File-based command queue for agent communication.
  Writes commands to ~/.claude/inbox/ and polls responses from ~/.claude/outbox/.
  """
  use GenServer
  require Logger

  @inbox_dir Path.expand("~/.claude/inbox")
  @outbox_dir Path.expand("~/.claude/outbox")
  @poll_interval 2000
  @inbox_ttl_sec 86_400
  @sweep_interval_ms :timer.hours(1)

  # ═══════════════════════════════════════════════════════
  # Client API
  # ═══════════════════════════════════════════════════════

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Write a command to the inbox for a specific session.
  Creates ~/.claude/inbox/{session_id}/{id}.json
  """
  def write_command(session_id, command) when is_map(command) do
    GenServer.call(__MODULE__, {:write_command, session_id, command})
  end

  @doc """
  Write a message to a team agent's inbox in Claude Code native format.
  Creates ~/.claude/teams/{team}/inboxes/{agent_name}.json
  """
  def write_team_message(team_name, agent_name, message) when is_map(message) do
    GenServer.call(__MODULE__, {:write_team_message, team_name, agent_name, message})
  end

  @doc """
  Delete a message from a team agent's inbox by index.
  """
  def delete_team_message(team_name, agent_name, message_index) do
    GenServer.call(__MODULE__, {:delete_team_message, team_name, agent_name, message_index})
  end

  @doc """
  Get per-session queue statistics from the inbox directory.
  Returns a list of %{session_id, pending_count, oldest_age_sec}.
  """
  def get_queue_stats do
    now = System.os_time(:second)

    list_session_dirs(@inbox_dir)
    |> Enum.map(fn session_id ->
      session_inbox = Path.join(@inbox_dir, session_id)

      files =
        case File.ls(session_inbox) do
          {:ok, entries} -> Enum.filter(entries, &String.ends_with?(&1, ".json"))
          _ -> []
        end

      oldest_age =
        case files do
          [] ->
            0

          fs ->
            oldest_mtime =
              fs
              |> Enum.map(fn f ->
                case File.stat(Path.join(session_inbox, f), time: :posix) do
                  {:ok, %{mtime: mtime}} -> mtime
                  _ -> now
                end
              end)
              |> Enum.min()

            now - oldest_mtime
        end

      %{
        session_id: session_id,
        pending_count: length(files),
        oldest_age_sec: oldest_age
      }
    end)
    |> Enum.filter(fn s -> s.pending_count > 0 end)
  end

  # ═══════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    ensure_directories()
    schedule_poll()
    Process.send_after(self(), :sweep_inbox, @sweep_interval_ms)
    {:ok, %{last_poll: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:write_command, session_id, command}, _from, state) do
    result = do_write_command(session_id, command)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:write_team_message, team_name, agent_name, message}, _from, state) do
    result = do_write_team_message(team_name, agent_name, message)
    {:reply, result, state}
  end

  @impl true
  def handle_call({:delete_team_message, team_name, agent_name, message_index}, _from, state) do
    result = do_delete_team_message(team_name, agent_name, message_index)
    {:reply, result, state}
  end

  @impl true
  def handle_info(:poll_outbox, state) do
    # Poll all session outbox directories
    session_dirs = list_session_dirs(@outbox_dir)

    Enum.each(session_dirs, fn session_id ->
      responses = do_poll_responses(session_id)

      if length(responses) > 0 do
        Logger.debug("CommandQueue: Found #{length(responses)} responses for #{session_id}")

        # Broadcast responses to interested parties
        Phoenix.PubSub.broadcast(
          Observatory.PubSub,
          "session:#{session_id}",
          {:command_responses, responses}
        )
      end
    end)

    schedule_poll()
    {:noreply, %{state | last_poll: DateTime.utc_now()}}
  end

  @impl true
  def handle_info(:sweep_inbox, state) do
    Process.send_after(self(), :sweep_inbox, @sweep_interval_ms)

    if map_size(Observatory.TeamWatcher.get_state()) == 0 do
      now = System.os_time(:second)
      cutoff = now - @inbox_ttl_sec

      list_session_dirs(@inbox_dir)
      |> Enum.each(fn session_id ->
        session_dir = Path.join(@inbox_dir, session_id)

        case File.ls(session_dir) do
          {:ok, files} ->
            Enum.each(files, fn file ->
              path = Path.join(session_dir, file)

              case File.stat(path, time: :posix) do
                {:ok, %{mtime: mtime}} when mtime < cutoff ->
                  File.rm(path)

                _ ->
                  :ok
              end
            end)

            # Remove the session dir if now empty
            case File.ls(session_dir) do
              {:ok, []} -> File.rmdir(session_dir)
              _ -> :ok
            end

          _ ->
            :ok
        end
      end)
    end

    {:noreply, state}
  end

  # ═══════════════════════════════════════════════════════
  # Helpers
  # ═══════════════════════════════════════════════════════

  defp ensure_directories do
    File.mkdir_p!(@inbox_dir)
    File.mkdir_p!(@outbox_dir)
  end

  defp schedule_poll do
    Process.send_after(self(), :poll_outbox, @poll_interval)
  end

  defp do_write_command(session_id, command) do
    session_inbox = Path.join(@inbox_dir, session_id)
    File.mkdir_p!(session_inbox)

    command_id = generate_id()
    file_path = Path.join(session_inbox, "#{command_id}.json")

    command_with_id =
      Map.merge(command, %{
        id: command_id,
        session_id: session_id,
        timestamp: DateTime.utc_now() |> DateTime.to_iso8601()
      })

    case Jason.encode(command_with_id, pretty: true) do
      {:ok, json} ->
        case File.write(file_path, json) do
          :ok ->
            Logger.debug("CommandQueue: Wrote command #{command_id} to #{file_path}")
            {:ok, command_with_id}

          {:error, reason} ->
            Logger.error("CommandQueue: Failed to write #{file_path}: #{inspect(reason)}")
            {:error, reason}
        end

      {:error, reason} ->
        Logger.error("CommandQueue: Failed to encode command: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp do_poll_responses(session_id) do
    session_outbox = Path.join(@outbox_dir, session_id)

    if File.dir?(session_outbox) do
      session_outbox
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn file ->
        file_path = Path.join(session_outbox, file)

        case File.read(file_path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, data} ->
                # Delete after reading (consume response)
                File.rm(file_path)
                data

              {:error, reason} ->
                Logger.error("CommandQueue: Failed to decode #{file_path}: #{inspect(reason)}")
                nil
            end

          {:error, reason} ->
            Logger.error("CommandQueue: Failed to read #{file_path}: #{inspect(reason)}")
            nil
        end
      end)
      |> Enum.reject(&is_nil/1)
    else
      []
    end
  end

  defp list_session_dirs(base_dir) do
    if File.dir?(base_dir) do
      base_dir
      |> File.ls!()
      |> Enum.filter(fn name ->
        File.dir?(Path.join(base_dir, name))
      end)
    else
      []
    end
  end

  defp generate_id do
    :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
  end

  defp do_write_team_message(team_name, agent_name, message) do
    inbox_dir = Path.expand("~/.claude/teams/#{team_name}/inboxes")
    File.mkdir_p!(inbox_dir)
    inbox_file = Path.join(inbox_dir, "#{agent_name}.json")

    # Read existing messages or start fresh
    existing =
      case File.read(inbox_file) do
        {:ok, content} ->
          case Jason.decode(content) do
            {:ok, messages} when is_list(messages) -> messages
            _ -> []
          end

        {:error, _} ->
          []
      end

    # Append new message in Claude Code native format
    native_message = %{
      "from" => message[:from] || message["from"] || "unknown",
      "text" => message[:content] || message["content"] || "",
      "timestamp" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "read" => false
    }

    updated = existing ++ [native_message]

    case Jason.encode(updated, pretty: true) do
      {:ok, json} -> File.write(inbox_file, json)
      {:error, reason} -> {:error, reason}
    end
  end

  defp do_delete_team_message(team_name, agent_name, message_index) do
    inbox_dir = Path.expand("~/.claude/teams/#{team_name}/inboxes")
    inbox_file = Path.join(inbox_dir, "#{agent_name}.json")

    case File.read(inbox_file) do
      {:ok, content} ->
        case Jason.decode(content) do
          {:ok, messages} when is_list(messages) ->
            updated = List.delete_at(messages, message_index)

            case Jason.encode(updated, pretty: true) do
              {:ok, json} -> File.write(inbox_file, json)
              {:error, reason} -> {:error, reason}
            end

          _ ->
            {:error, :invalid_inbox_format}
        end

      {:error, reason} ->
        {:error, reason}
    end
  end
end
