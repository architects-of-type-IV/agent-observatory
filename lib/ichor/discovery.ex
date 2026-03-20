defmodule Ichor.Discovery do
  @moduledoc """
  Introspects the application to find Ash Resources and Actions available
  for use in automation and Reactor workflows.
  """

  @type action_info :: %{
          name: atom(),
          type: atom(),
          primary?: boolean(),
          arguments: [atom()],
          accepts: [atom()],
          code_interface?: boolean(),
          tool?: boolean()
        }

  @type resource_info :: %{
          module: module(),
          name: String.t(),
          short_name: String.t(),
          actions: [action_info()]
        }

  @type domain_info :: %{
          module: module(),
          name: String.t(),
          short_name: String.t(),
          resources: [resource_info()],
          tools: [map()]
        }

  @doc "Returns the configured Ash domains."
  @spec domains() :: [module()]
  def domains do
    :ichor
    |> Application.get_env(:ash_domains, [])
    |> Enum.uniq()
  end

  @doc """
  Returns a flat list of available workflow steps, matching the shape used in
  the Genesis automation builder.
  """
  @spec available_steps() :: [map()]
  def available_steps do
    for domain <- domains(),
        resource <- Ash.Domain.Info.resources(domain),
        action <- Ash.Resource.Info.actions(resource),
        action.type in [:create, :update, :destroy, :read, :action],
        into: [] do
      %{
        id: "#{inspect(resource)}.#{action.name}",
        name: to_string(action.name),
        type: to_string(action.type),
        resource: inspect(resource),
        domain: inspect(domain),
        description: Map.get(action, :description) || "",
        arguments: action_arguments(action),
        inputs: action_arguments(action),
        resource_fields: resource_fields(resource),
        code_interface: code_interface?(resource, action.name),
        tool: tool?(domain, resource, action.name)
      }
    end
  end

  @doc "Returns the full discovery catalog."
  @spec catalog() :: [domain_info()]
  def catalog do
    domains()
    |> Enum.map(&domain/1)
    |> Enum.sort_by(& &1.short_name)
  end

  @doc "Returns discovery data for a single domain module."
  @spec domain(module()) :: domain_info()
  def domain(domain) when is_atom(domain) do
    tools = domain_tools(domain)
    tool_index = MapSet.new(Enum.map(tools, &{&1.resource, &1.action}))

    %{
      module: domain,
      name: inspect(domain),
      short_name: short_name(domain),
      resources:
        domain
        |> Ash.Domain.Info.resources()
        |> Enum.map(&resource(&1, tool_index))
        |> Enum.sort_by(& &1.short_name),
      tools: Enum.sort_by(tools, &to_string(&1.name))
    }
  end

  @doc "Resolves a domain by short or full name and returns its discovery data."
  @spec domain(String.t()) :: {:ok, domain_info()} | {:error, :unknown_domain}
  def domain(name) when is_binary(name) do
    case Enum.find(domains(), &matches_domain?(&1, name)) do
      nil -> {:error, :unknown_domain}
      domain -> {:ok, domain(domain)}
    end
  end

  defp resource(resource, tool_index) do
    %{
      module: resource,
      name: inspect(resource),
      short_name: short_name(resource),
      actions:
        resource
        |> Ash.Resource.Info.actions()
        |> Enum.map(fn action ->
          %{
            name: action.name,
            type: action.type,
            primary?: Map.get(action, :primary?, false),
            arguments: Enum.map(Map.get(action, :arguments, []), & &1.name),
            accepts: Map.get(action, :accept, []),
            code_interface?: code_interface?(resource, action.name),
            tool?: MapSet.member?(tool_index, {resource, action.name})
          }
        end)
        |> Enum.sort_by(&{Atom.to_string(&1.type), Atom.to_string(&1.name)})
    }
  end

  defp action_arguments(action) do
    for arg <- Map.get(action, :arguments, []) do
      %{
        name: to_string(arg.name),
        type: inspect(arg.type),
        required: not Map.get(arg, :allow_nil?, false)
      }
    end
  end

  defp resource_fields(resource) do
    for attr <- Ash.Resource.Info.attributes(resource) do
      to_string(attr.name)
    end
  end

  defp code_interface?(resource, action_name) do
    resource
    |> code_interfaces()
    |> Enum.any?(&(&1.name == action_name))
  end

  defp tool?(domain, resource, action_name) do
    domain
    |> domain_tools()
    |> Enum.any?(&(&1.resource == resource and &1.action == action_name))
  end

  defp code_interfaces(resource) do
    Spark.Dsl.Extension.get_entities(resource, [:code_interface]) || []
  end

  defp domain_tools(domain) do
    domain
    |> Spark.Dsl.Extension.get_entities([:tools])
    |> Enum.map(fn tool ->
      %{
        name: tool.name,
        resource: tool.resource,
        action: tool.action
      }
    end)
  rescue
    _ -> []
  end

  defp matches_domain?(domain, name) do
    inspect(domain) == name or short_name(domain) == name or String.downcase(short_name(domain)) == String.downcase(name)
  end

  defp short_name(module) do
    module
    |> inspect()
    |> String.split(".")
    |> List.last()
  end
end
