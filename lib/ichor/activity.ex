defmodule Ichor.Activity do
  use Ash.Domain

  resources do
    resource(Ichor.Activity.Message)
    resource(Ichor.Activity.Task)
    resource(Ichor.Activity.Error)
  end
end
