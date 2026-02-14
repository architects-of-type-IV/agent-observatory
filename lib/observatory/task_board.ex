defmodule Observatory.TaskBoard do
  use Ash.Domain

  resources do
    resource Observatory.TaskBoard.Task
  end
end
