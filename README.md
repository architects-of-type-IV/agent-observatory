# memories_client

Client for the Memories knowledge-graph API.

Extracted from the ICHOR IV agent observatory, where an app-manager agent used
it to record what it observed and recall it during conversations. No
dependencies — the HTTP transport is a behaviour, defaulting to OTP's `:httpc`.

## Three operations

| Call | Does |
|---|---|
| `ingest/2` | Write an observation into the graph |
| `search/2` | Retrieve matching facts or episodes |
| `query_memory/2` | Ask a natural-language question over the graph |

## Install

```elixir
def deps do
  [{:memories_client, path: "../memories_client"}]
end
```

Requires Elixir 1.18+ for the built-in `JSON` module.

```elixir
config :memories_client,
  url: "https://memories.example.com",
  api_key: {:system, "MEMORIES_API_KEY"},
  group_id: "archon",
  user_id: "archon"
```

`:api_key` accepts `{:system, "VAR"}` to read the environment at call time,
keeping the secret out of compiled config. A plain string also works.

## Use

```elixir
{:ok, result} = MemoriesClient.ingest("The deploy pipeline uses Oban.", source: "agent")
#=> %{episode_id: "e1", group_id: "archon", status: "ok", sync_status: "pending"}

{:ok, facts} = MemoriesClient.search("deploy pipeline", limit: 5)
#=> [%{uuid: "u1", fact: "Deploys use Oban", score: 0.87, ...}]

{:ok, answer} = MemoriesClient.query_memory("How do deploys work?")
#=> %{answer: "Via Oban.", citations: [...], context: %{...}}
```

### Options

- `search/2` — `:scope` (`"edges"` or `"episodes"`), `:limit`, `:user_id`
- `ingest/2` — `:type`, `:source`, `:space`, `:extraction_instructions`, `:user_id`
- `query_memory/2` — `:limit`

A long document may be split server-side; `ingest/2` then returns
`%{chunked: true, chunk_count: n, episodes: [...]}`. Check for the `:chunked`
key to tell the two shapes apart.

## Response normalisation

Responses come back as flat maps with atom keys, so callers never touch raw JSON
string keys. Fields the server omits are present as `nil` rather than absent —
so `result.score` is always safe, and a caller can pattern-match without first
checking that a key exists.

Errors are uniform:

- `{:error, {:http_error, status, body}}` — the server answered with a non-2xx;
  the body is decoded when it is JSON, and passed through when it is not
- `{:error, reason}` — no response arrived at all

Status 200–202 counts as success. `202` matters: ingest is asynchronous
server-side, and accepting the episode is the expected reply.

## Swapping the HTTP transport

The client builds requests and maps responses; moving the bytes is somebody
else's problem. The default `:httpc` adapter has no dependencies and is fine for
low volume. For anything busy, point `:http` at your own adapter and inherit its
pooling, retries, and telemetry:

```elixir
defmodule MyApp.ReqAdapter do
  @behaviour MemoriesClient.HTTP

  @impl true
  def post(url, body, headers) do
    case Req.post(url, body: body, headers: headers) do
      {:ok, %{status: status, body: body}} -> {:ok, status, body}
      {:error, reason} -> {:error, reason}
    end
  end
end

config :memories_client, http: MyApp.ReqAdapter
```

Return `{:ok, status, body}` for *any* completed request, including 4xx and 5xx —
the client decides what counts as a failure. The body may be a raw string or an
already-decoded map; adapters that decode JSON themselves need no special
handling.

### The default adapter

`MemoriesClient.HTTP.Httpc` verifies TLS against the OS certificate store via
`:public_key.cacerts_get/0`. Timeouts default to 30 s request and 15 s connect:

```elixir
config :memories_client,
  timeout_ms: 30_000,
  connect_timeout_ms: 15_000,
  httpc_ssl_options: [...]   # only if you need a custom CA bundle
```

## Wire format

The API is AshJsonApi, so requests are `application/vnd.api+json` with a
`{"data": {...}}` envelope and a bearer token. That is handled internally;
callers pass plain values.

## Tests

```
mix test
```

31 tests covering request shaping (URL, headers, envelope, defaults and
overrides), response normalisation for all three calls including the chunked
ingest shape, and every error path. They run against a stub adapter that records
requests, so no server is needed.

## Changes from the original

- Namespace `Ichor.Infrastructure.MemoriesClient` → `MemoriesClient`.
- Req replaced by the `MemoriesClient.HTTP` behaviour, with an `:httpc` adapter
  as the default — this is what makes the project dependency-free.
- Configuration moved from a nested `config :ichor, :memories` keyword list to
  flat `:memories_client` keys, with `{:system, "VAR"}` support for the API key
  and an error that names the missing key.
- The `MemoriesOperations` Ash resource wrapper was dropped; it re-mapped every
  result back to string keys purely to satisfy Ash's action types, which has no
  meaning outside that host.

Fixed along the way:

- **A non-list search response leaked out unnormalised.** `search/2` guarded on
  `is_list(results)` inside a `with`, so a non-list response fell through the
  guard and was returned raw, bypassing the mapping. Results are now always
  normalised to a list.
- **An undecodable body raised.** Decoding is now attempted and the raw body
  passed through on failure, so a proxy returning an HTML error page yields
  `{:error, {:http_error, 502, "<html>..."}}` rather than an exception.
- `:user_id` can now be overridden per call; it was previously always the
  configured default.
