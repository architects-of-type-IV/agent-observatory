defmodule Observatory.Activity do
  use Ash.Domain

  resources do
    resource Observatory.Activity.Message
    resource Observatory.Activity.Task
    resource Observatory.Activity.Error
  end
end
