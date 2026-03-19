defmodule Ichor.Mes.SubsystemScaffold do
  @moduledoc """
  Creates standalone Mix project directories for subsystems.
  Side-effect boundary: delegates content to Templates, isolates File I/O here.
  Idempotent: skips if mix.exs already exists.
  """

  alias Ichor.Mes.SubsystemScaffold.Templates

  @subsystems_dir "subsystems"

  @spec scaffold(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def scaffold(app_name, module_name) do
    path = subsystem_path(app_name)
    mix_exs = Path.join(path, "mix.exs")

    case File.exists?(mix_exs) do
      true -> {:ok, path}
      false -> create_project(path, app_name, module_name)
    end
  end

  @spec derive_names(String.t()) :: {String.t(), String.t()}
  def derive_names(title) do
    app_name =
      title
      |> String.downcase()
      |> String.replace(~r/[^a-z0-9]+/, "_")
      |> String.trim("_")

    module_name = "Ichor.Subsystems.#{Macro.camelize(app_name)}"
    {app_name, module_name}
  end

  @spec subsystem_path(String.t()) :: String.t()
  def subsystem_path(app_name), do: Path.join(@subsystems_dir, app_name)

  defp create_project(path, app_name, module_name) do
    lib_dir = Path.join(path, "lib")

    with :ok <- File.mkdir_p(lib_dir),
         :ok <- write_file(path, "mix.exs", Templates.mix_exs(app_name, module_name)),
         :ok <- write_file(path, ".formatter.exs", Templates.formatter()),
         :ok <- write_file(path, ".gitignore", Templates.gitignore()),
         :ok <- write_file(path, "README.md", Templates.readme(app_name, module_name)),
         :ok <- write_file(path, "integration.md", Templates.integration(app_name, module_name)),
         :ok <-
           write_file(
             lib_dir,
             "#{app_name}.ex",
             Templates.module_placeholder(app_name, module_name)
           ) do
      {:ok, path}
    else
      {:error, reason} -> {:error, "Failed to scaffold #{app_name}: #{inspect(reason)}"}
    end
  end

  defp write_file(dir, filename, content) do
    path = Path.join(dir, filename)

    case File.write(path, content) do
      :ok -> :ok
      {:error, reason} -> {:error, "#{path}: #{inspect(reason)}"}
    end
  end
end
