defmodule MemoriesClient.StubHTTP do
  @moduledoc """
  `MemoriesClient.HTTP` adapter that records requests and replays canned responses.

  Lets tests assert on the exact bytes sent — URL, headers, envelope — without a
  server, which is the part of a client worth testing.

  Responses are queued per test process, so tests stay isolated.
  """

  @behaviour MemoriesClient.HTTP

  @impl true
  def post(url, body, headers) do
    :ets.insert(table(), {{key(), :request, seq()}, %{url: url, body: body, headers: headers}})

    case pop_response() do
      nil -> {:ok, 200, "{}"}
      response -> response
    end
  end

  @doc "Start with a clean slate for this test process."
  def setup do
    if :ets.whereis(table()) == :undefined do
      :ets.new(table(), [:named_table, :public, :ordered_set])
    end

    :ets.match_delete(table(), {{key(), :_, :_}, :_})
    :ets.insert(table(), {{key(), :responses, 0}, []})
    :ok
  end

  @doc "Queue a response, returned by the next call in order."
  def stub(status, body) do
    responses = queued_responses() ++ [{:ok, status, body}]
    :ets.insert(table(), {{key(), :responses, 0}, responses})
    :ok
  end

  @doc "Queue a transport failure."
  def stub_error(reason) do
    responses = queued_responses() ++ [{:error, reason}]
    :ets.insert(table(), {{key(), :responses, 0}, responses})
    :ok
  end

  @doc "Every recorded request, oldest first."
  def requests do
    table()
    |> :ets.match_object({{key(), :request, :_}, :_})
    |> Enum.map(fn {_k, request} -> request end)
  end

  @doc "The most recent request."
  def last_request, do: List.last(requests())

  @doc "The most recent request's body, JSON-decoded."
  def last_body, do: last_request().body |> JSON.decode!()

  defp pop_response do
    case queued_responses() do
      [] ->
        nil

      [next | rest] ->
        :ets.insert(table(), {{key(), :responses, 0}, rest})
        next
    end
  end

  defp queued_responses do
    case :ets.lookup(table(), {key(), :responses, 0}) do
      [{_k, responses}] -> responses
      [] -> []
    end
  end

  defp seq, do: :erlang.unique_integer([:monotonic, :positive])
  defp key, do: self()
  defp table, do: :memories_client_stub_http
end
