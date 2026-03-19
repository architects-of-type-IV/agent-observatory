defmodule Ichor.Projects.SubsystemLoader do
  @moduledoc """
  Compiles a subsystem Mix project and hot-loads its BEAM modules
  into the running VM without restart.

  Pipeline: compile -> add ebin to code path -> load modules -> call start/0.
  """

  require Logger

  alias Ichor.Signals

  @subsystems_dir Path.expand("subsystems")

  @spec compile_and_load(struct() | map()) :: {:ok, [module()]} | {:error, String.t()}
  def compile_and_load(project) do
    path = project.path || Path.join(@subsystems_dir, project.subsystem)

    with :ok <- validate_path(path),
         {:ok, _output} <- compile_project(path),
         {:ok, ebin_dir} <- find_ebin(path),
         {:ok, modules} <- load_modules(ebin_dir) do
      Signals.emit(:mes_subsystem_loaded, %{
        project_id: project.id,
        subsystem: project.subsystem,
        modules: Enum.map(modules, &inspect/1)
      })

      Logger.info("[MES.SubsystemLoader] Loaded #{length(modules)} modules from #{path}")
      {:ok, modules}
    end
  end

  @spec subsystems_dir() :: String.t()
  def subsystems_dir, do: @subsystems_dir

  defp validate_path(path) do
    cond do
      not File.dir?(path) -> {:error, "Project directory not found: #{path}"}
      not File.exists?(Path.join(path, "mix.exs")) -> {:error, "No mix.exs found in #{path}"}
      true -> :ok
    end
  end

  defp compile_project(path) do
    case System.cmd("mix", ["compile", "--warnings-as-errors"],
           cd: path,
           stderr_to_stdout: true,
           env: [{"MIX_ENV", "dev"}]
         ) do
      {output, 0} -> {:ok, output}
      {output, _code} -> {:error, "Compilation failed:\n#{output}"}
    end
  end

  defp find_ebin(path) do
    app_name = detect_app_name(path)
    ebin = Path.join([path, "_build", "dev", "lib", app_name, "ebin"])

    if File.dir?(ebin) do
      {:ok, ebin}
    else
      {:error, "ebin directory not found: #{ebin}"}
    end
  end

  defp detect_app_name(path) do
    mix_exs = Path.join(path, "mix.exs")

    case File.read(mix_exs) do
      {:ok, content} ->
        case Regex.run(~r/app:\s*:(\w+)/, content) do
          [_, name] -> name
          _ -> Path.basename(path)
        end

      _ ->
        Path.basename(path)
    end
  end

  defp load_modules(ebin_dir) do
    modules =
      ebin_dir
      |> File.ls!()
      |> Enum.filter(&String.ends_with?(&1, ".beam"))
      |> Enum.map(fn beam_file ->
        beam_file |> String.replace_suffix(".beam", "") |> String.to_atom()
      end)
      |> Enum.reject(&host_module?/1)
      |> Enum.map(fn module_name ->
        beam_path = Path.join(ebin_dir, "#{module_name}.beam")

        case :code.load_abs(String.to_charlist(String.replace_suffix(beam_path, ".beam", ""))) do
          {:module, module} -> module
          {:error, reason} -> raise "Failed to load #{module_name}: #{inspect(reason)}"
        end
      end)

    {:ok, modules}
  end

  defp host_module?(module_name) do
    name_str = Atom.to_string(module_name)

    # Only load Ichor.Subsystems.* modules -- everything else is a stub
    not String.starts_with?(name_str, "Elixir.Ichor.Subsystems.")
  end
end
