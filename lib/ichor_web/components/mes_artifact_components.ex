defmodule IchorWeb.Components.MesArtifactComponents do
  @moduledoc "Public API for MES artifact rendering. Delegates to specialized sub-modules."

  defdelegate reader_sidebar(assigns), to: IchorWeb.Components.MesReaderComponents
end
