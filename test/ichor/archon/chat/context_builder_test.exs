defmodule Ichor.Archon.Chat.ContextBuilderTest do
  use ExUnit.Case, async: false

  alias Ichor.Archon.Chat.ContextBuilder

  setup do
    Application.put_env(
      :ichor,
      :archon_memories_client_module,
      Ichor.TestSupport.ArchonStubMemoriesClient
    )

    Application.put_env(:ichor, :archon_test_pid, self())

    on_exit(fn ->
      Application.delete_env(:ichor, :archon_memories_client_module)
      Application.delete_env(:ichor, :archon_test_pid)
      Application.delete_env(:ichor, :archon_memories_responses)
    end)

    :ok
  end

  test "formats edge and episode retrieval into one system message" do
    Application.put_env(:ichor, :archon_memories_responses, %{
      "edges" => {:ok, [%{fact: "Operator reviewed MES brief"}]},
      "episodes" => {:ok, [%{"content" => "Discussed project priorities with the Architect"}]}
    })

    assert {:ok, [message]} = ContextBuilder.build_messages("what happened?")
    [content_part] = message.content
    assert content_part.content =~ "Facts:"
    assert content_part.content =~ "Operator reviewed MES brief"
    assert content_part.content =~ "Recent conversations:"
    assert content_part.content =~ "Discussed project priorities"
    assert_receive {:archon_memory_search, "what happened?", [scope: "edges", limit: 5]}
    assert_receive {:archon_memory_search, "what happened?", [scope: "episodes", limit: 3]}
  end

  test "returns no messages when searches are empty or fail" do
    Application.put_env(:ichor, :archon_memories_responses, %{
      "edges" => {:error, :timeout},
      "episodes" => {:ok, []}
    })

    assert {:ok, []} = ContextBuilder.build_messages("nothing")
  end
end
