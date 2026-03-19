defmodule Ichor.Mes do
  @moduledoc """
  Ash Domain: Manufacturing Execution System.

  Continuous manufacturing nervous system that autonomously spawns agent teams
  to research and propose new Ichor subsystems. Completed projects are hot-loaded
  into the running BEAM as standalone Mix projects.
  """

  use Ash.Domain, validate_config_inclusion?: false

  resources do
    resource(Ichor.Mes.Project)
  end

  @spec get_project(String.t()) :: {:ok, Ichor.Mes.Project.t()} | {:error, term()}
  def get_project(id), do: Ichor.Mes.Project.get(id)

  @spec create_project(map()) :: {:ok, Ichor.Mes.Project.t()} | {:error, term()}
  def create_project(attrs), do: Ichor.Mes.Project.create(attrs)

  @spec list_projects() :: list(Ichor.Mes.Project.t())
  def list_projects, do: Ichor.Mes.Project.list_all!()

  @spec loaded_projects() :: list(Ichor.Mes.Project.t())
  def loaded_projects do
    case Ichor.Mes.Project.by_status(:loaded) do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @spec all_projects() :: list(Ichor.Mes.Project.t())
  def all_projects do
    case Ichor.Mes.Project.list_all() do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @spec mark_loaded(Ichor.Mes.Project.t()) :: {:ok, Ichor.Mes.Project.t()} | {:error, term()}
  def mark_loaded(project), do: Ichor.Mes.Project.mark_loaded(project)

  @spec mark_failed(Ichor.Mes.Project.t(), String.t()) ::
          {:ok, Ichor.Mes.Project.t()} | {:error, term()}
  def mark_failed(project, build_log), do: Ichor.Mes.Project.mark_failed(project, build_log)
end
