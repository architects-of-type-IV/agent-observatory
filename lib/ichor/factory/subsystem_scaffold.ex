defmodule Ichor.Factory.SubsystemScaffold do
  @moduledoc """
  Creates standalone Mix project directories for subsystems.
  Side-effect boundary: isolates File I/O here; template rendering is private.
  Idempotent: skips if mix.exs already exists.
  """

  @subsystems_dir "subsystems"

  @doc "Creates a standalone Mix project for app_name/module_name; idempotent."
  @spec scaffold(String.t(), String.t()) :: {:ok, String.t()} | {:error, String.t()}
  def scaffold(app_name, module_name) do
    path = subsystem_path(app_name)
    mix_exs = Path.join(path, "mix.exs")

    case File.exists?(mix_exs) do
      true -> {:ok, path}
      false -> create_project(path, app_name, module_name)
    end
  end

  @doc "Derives `{app_name, module_name}` from a human-readable title string."
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

  @doc "Returns the filesystem path for a subsystem by its app name."
  @spec subsystem_path(String.t()) :: String.t()
  def subsystem_path(app_name), do: Path.join(@subsystems_dir, app_name)

  # Private -- file creation

  defp create_project(path, app_name, module_name) do
    lib_dir = Path.join(path, "lib")

    with :ok <- File.mkdir_p(lib_dir),
         :ok <- write_file(path, "mix.exs", tpl_mix_exs(app_name, module_name)),
         :ok <- write_file(path, ".formatter.exs", tpl_formatter()),
         :ok <- write_file(path, ".gitignore", tpl_gitignore()),
         :ok <- write_file(path, "README.md", tpl_readme(app_name, module_name)),
         :ok <- write_file(path, "integration.md", tpl_integration(app_name, module_name)),
         :ok <-
           write_file(
             lib_dir,
             "#{app_name}.ex",
             tpl_module_placeholder(app_name, module_name)
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

  # Private -- template rendering (pure, String.t() -> String.t())

  defp tpl_mix_exs(app_name, module_name) do
    """
    defmodule #{module_name}.MixProject do
      use Mix.Project

      def project do
        [
          app: :#{app_name},
          version: "0.1.0",
          elixir: "~> 1.19",
          start_permanent: Mix.env() == :prod,
          deps: deps()
        ]
      end

      def application do
        [
          extra_applications: [:logger]
        ]
      end

      defp deps do
        [
          {:ichor_contracts, path: "../ichor_contracts"}
        ]
      end
    end
    """
  end

  defp tpl_module_placeholder(app_name, module_name) do
    """
    defmodule #{module_name} do
      @moduledoc \"\"\"
      #{humanize(app_name)} subsystem.
      Implements the Ichor.Mes.Subsystem behaviour for hot-loading into the BEAM.
      \"\"\"

      @behaviour Ichor.Mes.Subsystem

      @impl true
      def info do
        %Ichor.Mes.Subsystem.Info{
          name: "#{humanize(app_name)}",
          module: __MODULE__,
          description: "#{humanize(app_name)} subsystem",
          topic: "subsystem:#{app_name}",
          version: "0.1.0",
          signals_emitted: [],
          signals_subscribed: [],
          features: [],
          use_cases: [],
          dependencies: [Ichor.Signals]
        }
      end

      @impl true
      def start, do: :ok

      @impl true
      def handle_signal(_message), do: :ok

      @impl true
      def stop, do: :ok
    end
    """
  end

  defp tpl_formatter do
    """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end

  defp tpl_gitignore do
    """
    /_build/
    /deps/
    *.beam
    """
  end

  defp tpl_readme(app_name, module_name) do
    """
    # #{humanize(app_name)}

    Standalone ICHOR subsystem. Implements `Ichor.Mes.Subsystem` behaviour.

    ## Build

    ```bash
    mix compile --warnings-as-errors
    ```

    ## Module

    `#{module_name}` -- hot-loaded into the ICHOR BEAM via `SubsystemLoader`.

    ## Signals

    This subsystem communicates with the host via the Signal bus.
    No compile-time dependency on the host app.
    Stubs in `lib/ichor/` provide the behaviour and struct definitions for standalone compilation.
    """
  end

  defp tpl_integration(app_name, module_name) do
    """
    # Integration Guide: #{humanize(app_name)}

    ## Hot-Loading

    After build, load into the running BEAM:

    ```elixir
    {:ok, project} = Ichor.Factory.Project.get(project_id)
    Ichor.Factory.SubsystemLoader.compile_and_load(project)
    ```

    ## Signal Interface

    Subscribe to: `subsystem:#{app_name}`

    ```elixir
    Phoenix.PubSub.subscribe(Ichor.PubSub, "subsystem:#{app_name}")
    ```

    ## Module API

    ```elixir
    #{module_name}.info()   # Returns %Ichor.Mes.Subsystem.Info{}
    #{module_name}.start()  # Starts the subsystem GenServer
    #{module_name}.stop()   # Stops the subsystem
    ```

    ## Dashboard Integration

    To mount this subsystem's UI in the observatory dashboard,
    add the appropriate LiveView route or component mount point.
    This is a host app concern -- not part of the subsystem build.
    """
  end

  defp humanize(app_name) do
    app_name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
