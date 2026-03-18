defmodule Ichor.Activity do
  use Ash.Domain
  @moduledoc false

  resources do
    resource(Ichor.Activity.Message)
    resource(Ichor.Activity.Task)
    resource(Ichor.Activity.Error)
  end

  @spec list_recent_messages() :: list(Ichor.Activity.Message.t())
  def list_recent_messages, do: Ichor.Activity.Message.recent!()

  @spec list_current_tasks() :: list(Ichor.Activity.Task.t())
  def list_current_tasks, do: Ichor.Activity.Task.current!()

  @spec list_recent_errors() :: list(Ichor.Activity.Error.t())
  def list_recent_errors, do: Ichor.Activity.Error.recent!()

  @spec list_error_groups() :: list(map())
  def list_error_groups, do: Ichor.Activity.Error.by_tool!()
end
