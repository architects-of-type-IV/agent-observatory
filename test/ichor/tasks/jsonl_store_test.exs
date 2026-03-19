defmodule Ichor.Tasks.JsonlStoreTest do
  use ExUnit.Case, async: false

  alias Ichor.Tasks.JsonlStore

  setup do
    dir = Path.join(System.tmp_dir!(), "ichor-jsonl-#{System.unique_integer([:positive])}")
    File.mkdir_p!(dir)
    path = Path.join(dir, "tasks.jsonl")

    File.write!(
      path,
      Jason.encode!(%{"id" => "t1", "status" => "in_progress", "owner" => "alice"}) <> "\n"
    )

    on_exit(fn -> File.rm_rf(dir) end)

    %{path: path}
  end

  test "update_task_status rewrites jsonl line in place", %{path: path} do
    assert :ok = JsonlStore.update_task_status(path, "t1", "pending", "")

    [line] = path |> File.read!() |> String.split("\n", trim: true)
    {:ok, decoded} = Jason.decode(line)

    assert decoded["status"] == "pending"
    assert decoded["owner"] == ""
    assert is_binary(decoded["updated"])
  end
end
