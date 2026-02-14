defmodule Observatory.Messaging do
  use Ash.Domain

  resources do
    resource Observatory.Messaging.Message
  end
end
