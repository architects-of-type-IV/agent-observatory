defmodule Ichor.Mes.SubsystemScaffold.Templates do
  @moduledoc """
  Pure template rendering for standalone subsystem Mix projects.
  Every function is String.t() in -> String.t() out, zero side effects.
  """

  @spec mix_exs(String.t(), String.t()) :: String.t()
  def mix_exs(app_name, module_name) do
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

  @spec module_placeholder(String.t(), String.t()) :: String.t()
  def module_placeholder(app_name, module_name) do
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

  @spec formatter() :: String.t()
  def formatter do
    """
    [
      inputs: ["{mix,.formatter}.exs", "{config,lib,test}/**/*.{ex,exs}"]
    ]
    """
  end

  @spec gitignore() :: String.t()
  def gitignore do
    """
    /_build/
    /deps/
    *.beam
    """
  end

  @spec readme(String.t(), String.t()) :: String.t()
  def readme(app_name, module_name) do
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

  @spec integration(String.t(), String.t()) :: String.t()
  def integration(app_name, module_name) do
    """
    # Integration Guide: #{humanize(app_name)}

    ## Hot-Loading

    After build, load into the running BEAM:

    ```elixir
    {:ok, project} = Ichor.Mes.get_project(project_id)
    Ichor.Mes.SubsystemLoader.compile_and_load(project)
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
