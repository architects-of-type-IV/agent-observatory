defmodule TmuxChannel.Config do
  @moduledoc """
  Runtime configuration for `TmuxChannel`.

  Every value has a working default, so the library needs no configuration to
  run. Override any of them under the `:tmux_channel` application key:

      config :tmux_channel,
        socket_path: "~/.myapp/tmux/myapp.sock",
        server_name: "myapp",
        buffer_prefix: "myapp",
        server_cache_ttl_ms: 5_000,
        paste_settle_ms: 150,
        permission_profiles: %{
          "builder" => ["--dangerously-skip-permissions"],
          "scout" => ["--allowedTools", "Read", "Glob", "Grep"]
        }

  ## Server resolution

  Commands are tried against each server in `server_arg_sets/0` order:

    1. `-S <socket_path>` — only when the socket file exists
    2. `-L <server_name>` — named server
    3. `[]` — the default tmux server

  The first server that exits 0 wins.
  """

  @default_socket_path "~/.tmux_channel/tmux.sock"
  @default_server_name "tmux_channel"
  @default_buffer_prefix "tmux-channel"
  @default_cache_ttl_ms 5_000
  @default_paste_settle_ms 150

  @default_permission_profiles %{
    "builder" => ["--dangerously-skip-permissions"],
    "lead" => ["--dangerously-skip-permissions"],
    "coordinator" => ["--dangerously-skip-permissions"],
    "scout" => [
      "--allowedTools",
      "Read",
      "Glob",
      "Grep",
      "WebSearch",
      "WebFetch",
      "Bash"
    ]
  }

  @doc "Absolute path of the explicit tmux socket, expanded from `~`."
  @spec socket_path() :: String.t()
  def socket_path, do: Path.expand(get(:socket_path, @default_socket_path))

  @doc "Name of the tmux server passed to `-L`."
  @spec server_name() :: String.t()
  def server_name, do: get(:server_name, @default_server_name)

  @doc "Prefix used when generating unique tmux buffer names for delivery."
  @spec buffer_prefix() :: String.t()
  def buffer_prefix, do: get(:buffer_prefix, @default_buffer_prefix)

  @doc "How long a resolved server list stays cached in the calling process, in ms."
  @spec server_cache_ttl_ms() :: non_neg_integer()
  def server_cache_ttl_ms, do: get(:server_cache_ttl_ms, @default_cache_ttl_ms)

  @doc """
  Milliseconds to wait after `paste-buffer` before sending Enter.

  tmux pastes asynchronously; sending Enter too early submits an empty line.
  """
  @spec paste_settle_ms() :: non_neg_integer()
  def paste_settle_ms, do: get(:paste_settle_ms, @default_paste_settle_ms)

  @doc """
  Map of capability name to extra CLI arguments, used by `TmuxChannel.Script`.

  An unknown capability contributes no extra arguments.
  """
  @spec permission_profiles() :: %{optional(String.t()) => [String.t()]}
  def permission_profiles, do: get(:permission_profiles, @default_permission_profiles)

  @doc """
  Return the `[server_args, ...]` sets to try, in priority order.

  The socket entry is omitted when the socket file does not exist.
  """
  @spec server_arg_sets() :: [[String.t()]]
  def server_arg_sets do
    socket = socket_path()

    [
      if(File.exists?(socket), do: ["-S", socket]),
      ["-L", server_name()],
      []
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp get(key, default), do: Application.get_env(:tmux_channel, key, default)
end
