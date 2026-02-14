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
  Poll for responses from the outbox for a specific session.
  Reads from ~/.claude/outbox/{session_id}/*.json
  Returns list of response maps.
  """
  def poll_responses(session_id) do
    GenServer.call(__MODULE__, {:poll_responses, session_id})
  end

  @doc """
  Get all pending commands for a session (for debugging).
  """
  def get_pending_commands(session_id) do
    GenServer.call(__MODULE__, {:get_pending_commands, session_id})
  end

  # ═══════════════════════════════════════════════════════
  # Server Callbacks
  # ═══════════════════════════════════════════════════════

  @impl true
  def init(_opts) do
    ensure_directories()
    schedule_poll()
    {:ok, %{last_poll: DateTime.utc_now()}}
  end

  @impl true
  def handle_call({:write_command, session_id, command}, _from, state) do
    result = do_write_command(session_id, command)
    {:reply, result, state}
  end

  def handle_call({:poll_responses, session_id}, _from, state) do
    responses = do_poll_responses(session_id)
    {:reply, responses, state}
  end

  def handle_call({:get_pending_commands, session_id}, _from, state) do
    commands = do_get_pending_commands(session_id)
    {:reply, commands, state}
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

    command_with_id = Map.merge(command, %{
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

  defp do_get_pending_commands(session_id) do
    session_inbox = Path.join(@inbox_dir, session_id)

    if File.dir?(session_inbox) do
      session_inbox
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".json"))
      |> Enum.map(fn file ->
        file_path = Path.join(session_inbox, file)

        case File.read(file_path) do
          {:ok, content} ->
            case Jason.decode(content) do
              {:ok, data} -> data
              {:error, _} -> nil
            end

          {:error, _} ->
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
end
