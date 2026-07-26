defmodule MemoriesClientTest do
  use ExUnit.Case, async: false

  alias MemoriesClient.StubHTTP

  setup do
    Application.put_env(:memories_client, :url, "https://memories.example.com/")
    Application.put_env(:memories_client, :api_key, "secret-key")
    Application.put_env(:memories_client, :group_id, "archon")
    Application.put_env(:memories_client, :user_id, "archon-user")
    Application.put_env(:memories_client, :http, StubHTTP)

    :ok = StubHTTP.setup()

    on_exit(fn ->
      for key <- [:url, :api_key, :group_id, :user_id, :http] do
        Application.delete_env(:memories_client, key)
      end
    end)

    :ok
  end

  describe "request shaping" do
    test "wraps the body in the AshJsonApi data envelope" do
      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("anything")

      assert %{"data" => %{"query" => "anything"}} = StubHTTP.last_body()
    end

    test "sends the bearer token and vnd.api+json headers" do
      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("anything")

      headers = Map.new(StubHTTP.last_request().headers)
      assert headers["authorization"] == "Bearer secret-key"
      assert headers["content-type"] == "application/vnd.api+json"
      assert headers["accept"] == "application/vnd.api+json"
    end

    test "strips a trailing slash from the configured url" do
      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("anything")

      assert StubHTTP.last_request().url == "https://memories.example.com/api/graph/search"
    end

    test "resolves a {:system, VAR} api key at call time" do
      System.put_env("MEMORIES_TEST_KEY", "from-env")
      Application.put_env(:memories_client, :api_key, {:system, "MEMORIES_TEST_KEY"})
      on_exit(fn -> System.delete_env("MEMORIES_TEST_KEY") end)

      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("anything")

      assert Map.new(StubHTTP.last_request().headers)["authorization"] == "Bearer from-env"
    end

    test "raises a clear error when a {:system, VAR} key is unset" do
      Application.put_env(:memories_client, :api_key, {:system, "DEFINITELY_NOT_SET"})

      assert_raise ArgumentError, ~r/DEFINITELY_NOT_SET/, fn ->
        MemoriesClient.search("anything")
      end
    end

    test "raises naming the key when required config is missing" do
      Application.delete_env(:memories_client, :url)

      assert_raise ArgumentError, ~r/missing required configuration `:url`/, fn ->
        MemoriesClient.search("anything")
      end
    end
  end

  describe "search/2" do
    test "posts to the graph search path with defaults" do
      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("deploys")

      assert StubHTTP.last_request().url =~ "/api/graph/search"

      assert %{"data" => data} = StubHTTP.last_body()
      assert data["query"] == "deploys"
      assert data["scope"] == "edges"
      assert data["limit"] == 10
      assert data["user_id"] == "archon-user"
    end

    test "honours scope, limit, and user_id overrides" do
      StubHTTP.stub(200, "[]")
      {:ok, _} = MemoriesClient.search("deploys", scope: :episodes, limit: 3, user_id: "other")

      assert %{"data" => data} = StubHTTP.last_body()
      assert data["scope"] == "episodes"
      assert data["limit"] == 3
      assert data["user_id"] == "other"
    end

    test "normalises results to atom-keyed maps" do
      StubHTTP.stub(200, """
      [{"uuid": "u1", "fact": "Deploys use Oban", "name": "n", "source": "a",
        "target": "b", "score": 0.87, "created_at": "2026-01-01T00:00:00Z"}]
      """)

      assert {:ok, [result]} = MemoriesClient.search("deploys")
      assert result.uuid == "u1"
      assert result.fact == "Deploys use Oban"
      assert result.score == 0.87
      assert result.created_at == "2026-01-01T00:00:00Z"
    end

    test "fills missing fields with nil rather than omitting them" do
      StubHTTP.stub(200, ~s([{"uuid": "u1"}]))

      assert {:ok, [result]} = MemoriesClient.search("deploys")
      assert result.uuid == "u1"
      assert result.fact == nil
      assert result.score == nil
      assert Map.has_key?(result, :created_at)
    end

    test "an empty result set is an empty list" do
      StubHTTP.stub(200, "[]")

      assert {:ok, []} = MemoriesClient.search("nothing")
    end
  end

  describe "ingest/2" do
    test "posts to the ingest path with defaults" do
      StubHTTP.stub(200, ~s({"episode_id": "e1"}))
      {:ok, _} = MemoriesClient.ingest("The pipeline uses Oban.")

      assert StubHTTP.last_request().url =~ "/api/episodes/ingest"

      assert %{"data" => data} = StubHTTP.last_body()
      assert data["content"] == "The pipeline uses Oban."
      assert data["type"] == "text"
      assert data["source"] == "agent"
      assert data["user_id"] == "archon-user"
    end

    test "omits optional fields when not given" do
      StubHTTP.stub(200, "{}")
      {:ok, _} = MemoriesClient.ingest("content")

      %{"data" => data} = StubHTTP.last_body()
      refute Map.has_key?(data, "space")
      refute Map.has_key?(data, "extraction_instructions")
    end

    test "includes optional fields when given" do
      StubHTTP.stub(200, "{}")

      {:ok, _} =
        MemoriesClient.ingest("content",
          space: "eng",
          extraction_instructions: "focus on services",
          type: "markdown",
          source: "webhook"
        )

      %{"data" => data} = StubHTTP.last_body()
      assert data["space"] == "eng"
      assert data["extraction_instructions"] == "focus on services"
      assert data["type"] == "markdown"
      assert data["source"] == "webhook"
    end

    test "normalises a single-episode response" do
      StubHTTP.stub(200, """
      {"episode_id": "e1", "group_id": "archon", "status": "ok", "sync_status": "pending"}
      """)

      assert {:ok, result} = MemoriesClient.ingest("content")
      assert result.episode_id == "e1"
      assert result.group_id == "archon"
      assert result.status == "ok"
      assert result.sync_status == "pending"
      refute Map.has_key?(result, :chunked)
    end

    test "normalises a chunked response into per-episode entries" do
      StubHTTP.stub(200, """
      {"chunked": true, "chunk_count": 2,
       "episodes": [{"episode_id": "e1", "status": "ok"},
                    {"episode_id": "e2", "status": "ok"}]}
      """)

      assert {:ok, result} = MemoriesClient.ingest("a very long document")
      assert result.chunked == true
      assert result.chunk_count == 2
      assert [%{episode_id: "e1"}, %{episode_id: "e2"}] = result.episodes
    end

    test "a chunked response with no episodes yields an empty list" do
      StubHTTP.stub(200, ~s({"chunked": true, "chunk_count": 0}))

      assert {:ok, result} = MemoriesClient.ingest("content")
      assert result.episodes == []
    end
  end

  describe "query_memory/2" do
    test "posts to the query path with the default limit" do
      StubHTTP.stub(200, ~s({"answer": "yes"}))
      {:ok, _} = MemoriesClient.query_memory("How do deploys work?")

      assert StubHTTP.last_request().url =~ "/api/memories/query"

      assert %{"data" => data} = StubHTTP.last_body()
      assert data["query"] == "How do deploys work?"
      assert data["limit"] == 10
    end

    test "honours a limit override" do
      StubHTTP.stub(200, "{}")
      {:ok, _} = MemoriesClient.query_memory("q", limit: 3)

      assert StubHTTP.last_body()["data"]["limit"] == 3
    end

    test "normalises the answer, citations, and context" do
      StubHTTP.stub(200, """
      {"answer": "Via Oban.", "citations": [{"uuid": "u1"}], "context": {"depth": 2}}
      """)

      assert {:ok, result} = MemoriesClient.query_memory("q")
      assert result.answer == "Via Oban."
      assert result.citations == [%{"uuid" => "u1"}]
      assert result.context == %{"depth" => 2}
    end

    test "missing fields come back nil" do
      StubHTTP.stub(200, "{}")

      assert {:ok, %{answer: nil, citations: nil, context: nil}} =
               MemoriesClient.query_memory("q")
    end
  end

  describe "error handling" do
    test "a 4xx is returned as an http_error with the decoded body" do
      StubHTTP.stub(422, ~s({"errors": [{"detail": "bad query"}]}))

      assert {:error, {:http_error, 422, body}} = MemoriesClient.search("bad")
      assert body == %{"errors" => [%{"detail" => "bad query"}]}
    end

    test "a 5xx is returned as an http_error" do
      StubHTTP.stub(500, "internal error")

      assert {:error, {:http_error, 500, "internal error"}} = MemoriesClient.ingest("x")
    end

    test "a transport failure is passed through" do
      StubHTTP.stub_error(:timeout)

      assert {:error, :timeout} = MemoriesClient.search("anything")
    end

    test "an undecodable success body is returned as-is rather than raising" do
      StubHTTP.stub(200, "not json at all")

      assert {:ok, result} = MemoriesClient.query_memory("q")
      assert result.answer == nil
    end

    test "202 counts as success" do
      StubHTTP.stub(202, ~s({"episode_id": "e1", "status": "accepted"}))

      assert {:ok, %{episode_id: "e1"}} = MemoriesClient.ingest("content")
    end

    test "203 does not count as success" do
      StubHTTP.stub(203, "{}")

      assert {:error, {:http_error, 203, _}} = MemoriesClient.ingest("content")
    end
  end

  describe "adapters returning decoded bodies" do
    test "a map body is used without re-decoding" do
      StubHTTP.stub(200, %{"answer" => "already decoded"})

      assert {:ok, %{answer: "already decoded"}} = MemoriesClient.query_memory("q")
    end
  end

  describe "configuration accessors" do
    test "expose the configured ids" do
      assert MemoriesClient.group_id() == "archon"
      assert MemoriesClient.user_id() == "archon-user"
    end
  end

  describe "the httpc adapter" do
    test "implements the HTTP behaviour" do
      behaviours =
        MemoriesClient.HTTP.Httpc.module_info(:attributes)
        |> Keyword.get_values(:behaviour)
        |> List.flatten()

      assert MemoriesClient.HTTP in behaviours
    end

    test "is the default when none is configured" do
      Application.delete_env(:memories_client, :http)

      assert MemoriesClient.Config.http() == MemoriesClient.HTTP.Httpc
    end
  end
end
