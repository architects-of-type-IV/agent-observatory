defmodule Observatory.Annotations do
  use Ash.Domain

  resources do
    resource Observatory.Annotations.Note
  end
end
