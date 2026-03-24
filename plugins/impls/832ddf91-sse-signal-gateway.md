# Implementation Brief: SSE Signal Gateway
**Brief ID:** 832ddf91
**Plugin:** `Ichor.Subsystems.SseSignalGateway`
**Version:** 0.1.0

---

## Signal Catalog Additions

Add to `lib/ichor/signals/catalog.ex` under `@plugin_defs` (or a new `@sse_defs` map):

```elixir
@sse_defs %{
  sse_client_connected: %{
    category: :system,
    keys: [:client_id, :topics, :remote_ip],
    doc: "SSE client connected to signal gateway"
  },
  sse_client_disconnected: %{
    category: :system,
    keys: [:client_id, :topics],
    doc: "SSE client disconnected from signal gateway"
  },
  sse_client_count_changed: %{
    category: :system,
    keys: [:count],
    doc: "SSE active client count changed"
  }
}
```

Merge `@sse_defs` into `@signals`.

---

## Module Structure

```
lib/ichor/subsystems/sse_signal_gateway/
  gateway.ex             # GenServer: ETS client registry, max-connections cap
  controller.ex          # Phoenix controller action: SSE stream loop
```

Add route in `lib/ichor_web/router.ex`:

```elixir
get "/api/signals/stream", IchorWeb.SseSignalGateway.Controller, :stream
```

---

## Supervisor Registration

The `Gateway` GenServer is a singleton — add to the application supervision tree in `lib/ichor/application.ex` (or appropriate top-level supervisor, NOT Factory.LifecycleSupervisor which is factory-scoped):

```elixir
{Ichor.Subsystems.SseSignalGateway.Gateway, []},
```

The controller is stateless; no separate supervision needed.

---

## Gateway GenServer

```elixir
defmodule Ichor.Subsystems.SseSignalGateway.Gateway do
  use GenServer

  @max_connections 50
  @table :sse_client_registry

  defstruct count: 0

  def start_link(opts), do: GenServer.start_link(__MODULE__, opts, name: __MODULE__)

  @impl true
  def init(_opts) do
    :ets.new(@table, [:named_table, :public, :set])
    {:ok, %__MODULE__{}}
  end

  @doc "Returns {:ok, client_id} or {:error, :max_connections}."
  @spec register(pid(), [String.t()], String.t()) :: {:ok, String.t()} | {:error, :max_connections}
  def register(pid, topics, remote_ip) do
    GenServer.call(__MODULE__, {:register, pid, topics, remote_ip})
  end

  @spec unregister(String.t()) :: :ok
  def unregister(client_id), do: GenServer.cast(__MODULE__, {:unregister, client_id})

  @spec client_count() :: non_neg_integer()
  def client_count, do: GenServer.call(__MODULE__, :count)

  @impl true
  def handle_call({:register, pid, topics, remote_ip}, _from, state) do
    if state.count >= @max_connections do
      {:reply, {:error, :max_connections}, state}
    else
      client_id = :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
      :ets.insert(@table, {client_id, %{pid: pid, topics: topics, connected_at: DateTime.utc_now()}})
      Ichor.Signals.emit(:sse_client_connected, %{client_id: client_id, topics: topics, remote_ip: remote_ip})
      new_count = state.count + 1
      Ichor.Signals.emit(:sse_client_count_changed, %{count: new_count})
      {:reply, {:ok, client_id}, %{state | count: new_count}}
    end
  end

  @impl true
  def handle_call(:count, _from, state), do: {:reply, state.count, state}

  @impl true
  def handle_cast({:unregister, client_id}, state) do
    case :ets.lookup(@table, client_id) do
      [{^client_id, %{topics: topics}}] ->
        :ets.delete(@table, client_id)
        Ichor.Signals.emit(:sse_client_disconnected, %{client_id: client_id, topics: topics})
        new_count = max(0, state.count - 1)
        Ichor.Signals.emit(:sse_client_count_changed, %{count: new_count})
        {:noreply, %{state | count: new_count}}

      [] ->
        {:noreply, state}
    end
  end
end
```

---

## Controller (SSE stream loop)

```elixir
defmodule IchorWeb.SseSignalGateway.Controller do
  use IchorWeb, :controller

  alias Ichor.Subsystems.SseSignalGateway.Gateway
  alias Ichor.Signals.Message
  alias Ichor.Signals.Catalog

  @heartbeat_ms 15_000

  @doc """
  GET /api/signals/stream?topics=mes,fleet,agent

  Sends an infinite SSE stream. Client closes to disconnect.
  Optional topics param is a comma-separated list of category names.
  Defaults to all categories if omitted.
  """
  def stream(conn, params) do
    topics = parse_topics(params)
    remote_ip = conn.remote_ip |> Tuple.to_list() |> Enum.join(".")

    conn = conn
    |> put_resp_content_type("text/event-stream")
    |> put_resp_header("cache-control", "no-cache")
    |> put_resp_header("x-accel-buffering", "no")
    |> send_chunked(200)

    case Gateway.register(self(), topics, remote_ip) do
      {:error, :max_connections} ->
        # Connection already sent; best effort error frame
        chunk(conn, "event: error\ndata: max_connections\n\n")
        conn

      {:ok, client_id} ->
        Enum.each(topics, fn topic ->
          Phoenix.PubSub.subscribe(Ichor.PubSub, "signals:#{topic}")
        end)

        Process.send_after(self(), :heartbeat, @heartbeat_ms)
        stream_loop(conn, client_id, topics)
    end
  end

  defp stream_loop(conn, client_id, topics) do
    receive do
      %Message{} = msg ->
        frame = encode_sse(msg)
        case chunk(conn, frame) do
          {:ok, conn} ->
            stream_loop(conn, client_id, topics)

          {:error, _reason} ->
            cleanup(client_id, topics)
            conn
        end

      :heartbeat ->
        case chunk(conn, ": heartbeat\n\n") do
          {:ok, conn} ->
            Process.send_after(self(), :heartbeat, @heartbeat_ms)
            stream_loop(conn, client_id, topics)

          {:error, _reason} ->
            cleanup(client_id, topics)
            conn
        end

      _ ->
        stream_loop(conn, client_id, topics)
    end
  end

  defp cleanup(client_id, topics) do
    Enum.each(topics, fn topic ->
      Phoenix.PubSub.unsubscribe(Ichor.PubSub, "signals:#{topic}")
    end)
    Gateway.unregister(client_id)
  end

  defp encode_sse(%Message{name: name, data: data}) do
    payload = Jason.encode!(%{signal: name, data: data, ts: DateTime.utc_now()})
    "event: signal\ndata: #{payload}\n\n"
  end

  defp parse_topics(%{"topics" => topics_str}) do
    topics_str
    |> String.split(",")
    |> Enum.map(&String.trim/1)
    |> Enum.filter(&Catalog.valid_category?(String.to_atom(&1)))
  end

  defp parse_topics(_params) do
    Catalog.categories() |> Enum.map(&Atom.to_string/1)
  end
end
```

---

## PubSub Topic Format Note

The controller subscribes to `"signals:#{topic}"` (e.g., `"signals:mes"`, `"signals:fleet"`). This matches what `Ichor.Signals.Topics.category/1` produces — verify against `lib/ichor/signals/topics.ex` before implementing.

---

## Key Constraints

- The controller `stream_loop` runs in the **request process** (Cowboy handler), not a GenServer. This is correct — it is a long-lived HTTP connection.
- Never call `GenServer.call` from within `stream_loop` — risk of deadlock.
- `Gateway` ETS table is `:public` so the controller process can insert-free metadata reads if needed, but all mutations go through GenServer.
- `parse_topics/1` must guard against `String.to_atom` on arbitrary user input. Only convert atoms from the validated Catalog.categories() list:

```elixir
# Safe: only convert known category names
|> Enum.filter(fn t -> String.to_atom(t) in Catalog.categories() end)
|> Enum.map(&String.to_atom/1)
```

- The route must go under the `:api` pipeline (no CSRF), not the `:browser` pipeline.
- Operator auth (`Ichor.Infrastructure.Plugs.OperatorAuth`) should guard the route.

---

## Router Addition

```elixir
scope "/api", IchorWeb do
  pipe_through [:api, :operator_auth]
  get "/signals/stream", SseSignalGateway.Controller, :stream
end
```

---

## Verification

```bash
mix compile --warnings-as-errors
# Smoke test:
# curl -N -H "x-operator-token: <token>" http://localhost:4005/api/signals/stream?topics=mes,fleet
# In another terminal:
# iex> Ichor.Signals.emit(:mes_tick, %{tick: 1, active_runs: 0})
# Expect SSE frame to appear in curl output.
```
