defmodule Ichor.Mes do
  @moduledoc """
  Ash Domain: Manufacturing Execution System.

  Continuous manufacturing nervous system that autonomously spawns agent teams
  to research and propose new Ichor subsystems. Completed projects are hot-loaded
  into the running BEAM as standalone Mix projects.
  """

  use Ash.Domain, validate_config_inclusion?: false

  alias Ichor.Mes.Project

  resources do
    resource(Ichor.Mes.Project)
  end

  @spec get_project(String.t()) :: {:ok, Project.t()} | {:error, term()}
  def get_project(id), do: Project.get(id)

  @spec create_project(map()) :: {:ok, Project.t()} | {:error, term()}
  def create_project(attrs), do: Project.create(attrs)

  @spec list_projects() :: list(Project.t())
  def list_projects, do: Project.list_all!()

  @spec loaded_projects() :: list(Project.t())
  def loaded_projects do
    case Project.by_status(:loaded) do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @spec all_projects() :: list(Project.t())
  def all_projects do
    case Project.list_all() do
      {:ok, projects} -> projects
      _ -> []
    end
  end

  @spec mark_loaded(Project.t()) :: {:ok, Project.t()} | {:error, term()}
  def mark_loaded(project), do: Project.mark_loaded(project)

  @spec mark_failed(Project.t(), String.t()) ::
          {:ok, Project.t()} | {:error, term()}
  def mark_failed(project, build_log), do: Project.mark_failed(project, build_log)
end
