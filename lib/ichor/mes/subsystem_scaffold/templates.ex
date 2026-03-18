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
          deps: []
        ]
      end

      def application do
        [
          extra_applications: [:logger]
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

  @spec signals_stub() :: String.t()
  def signals_stub do
    ~S"""
    defmodule Ichor.Signals do
      @moduledoc "Stub for standalone compilation. Host VM provides real implementation."

      def emit(_name, _data), do: :ok
      def subscribe(_category), do: :ok
    end

    defmodule Ichor.Signals.Catalog do
      @moduledoc false
      def categories, do: []
    end

    defmodule Ichor.Signals.Topics do
      @moduledoc false
      def category(cat), do: "signal:#{cat}"
    end

    defmodule Ichor.Signals.Message do
      @moduledoc false
      defstruct [
        :name,
        :kind,
        :domain,
        :data,
        :timestamp,
        :source,
        :correlation_id,
        :causation_id,
        :meta
      ]
    end
    """
  end

  @spec subsystem_stub() :: String.t()
  def subsystem_stub do
    """
    defmodule Ichor.Mes.Subsystem do
      @moduledoc "Stub behaviour for standalone compilation. Replaced by host VM at runtime."

      @callback info() :: struct()
      @callback start() :: :ok | {:error, term()}
      @callback handle_signal(map()) :: :ok
      @callback stop() :: :ok
    end
    """
  end

  @spec info_stub() :: String.t()
  def info_stub do
    """
    defmodule Ichor.Mes.Subsystem.Info do
      @moduledoc "Stub struct for standalone compilation. Replaced by host VM at runtime."

      @enforce_keys [:name, :module, :description, :topic, :version]
      defstruct [
        :name,
        :module,
        :description,
        :topic,
        :version,
        :architecture,
        signals_emitted: [],
        signals_subscribed: [],
        features: [],
        use_cases: [],
        dependencies: []
      ]
    end
    """
  end

  @spec pubsub_stub() :: String.t()
  def pubsub_stub do
    ~S"""
    defmodule Ichor.PubSub do
      @moduledoc "Stub name for standalone compilation. Host VM provides Phoenix.PubSub."
    end

    unless Code.ensure_loaded?(Phoenix.PubSub) do
      defmodule Phoenix.PubSub do
        @moduledoc "Stub for standalone compilation."
        def unsubscribe(_pubsub, _topic), do: :ok
      end
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

  defp humanize(app_name) do
    app_name
    |> String.split("_")
    |> Enum.map_join(" ", &String.capitalize/1)
  end
end
