defmodule Ichor.MemoryStore.BlocksTest do
  use ExUnit.Case, async: false

  alias Ichor.MemoryStore.Blocks
  alias Ichor.MemoryStore.Tables

  setup do
    ensure_table(Tables.blocks_table())
    ensure_table(Tables.agents_table())

    on_exit(fn ->
      delete_table(Tables.blocks_table())
      delete_table(Tables.agents_table())
    end)

    :ok
  end

  test "builds and compiles blocks with stable shape" do
    block =
      Blocks.build(%{
        label: "persona",
        description: "agent instructions",
        value: "be precise",
        read_only: true
      })

    compiled = Blocks.compile([block])

    assert block.label == "persona"
    assert block.limit == Tables.default_block_limit()
    assert compiled =~ "<memory_block label=\"persona\""
    assert compiled =~ "be precise"
  end

  test "save_value enforces size limit" do
    {:ok, block} = Blocks.create(%{label: "notes", value: "x", limit: 3})
    assert {:error, :exceeds_limit} = Blocks.save_value(block, "toolong")
    assert {:ok, updated} = Blocks.save_value(block, "ok")
    assert updated.value == "ok"
  end

  defp ensure_table(name) do
    case :ets.info(name) do
      :undefined -> :ets.new(name, [:named_table, :public, :set])
      _ -> true
    end
  end

  defp delete_table(name) do
    case :ets.info(name) do
      :undefined -> :ok
      _ -> :ets.delete(name)
    end
  end
end
