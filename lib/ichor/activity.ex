defmodule Ichor.Activity do
  @moduledoc false
  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Activity.Error
  alias Ichor.Activity.Message
  alias Ichor.Activity.Task

  resources do
    resource(Ichor.Activity.Message)
    resource(Ichor.Activity.Task)
    resource(Ichor.Activity.Error)
  end

  @spec list_recent_messages() :: list(Message.t())
  def list_recent_messages, do: Message.recent!()

  @spec list_current_tasks() :: list(Task.t())
  def list_current_tasks, do: Task.current!()

  @spec list_recent_errors() :: list(Error.t())
  def list_recent_errors, do: Error.recent!()

  @spec list_error_groups() :: list(map())
  def list_error_groups, do: Error.by_tool!()
end
