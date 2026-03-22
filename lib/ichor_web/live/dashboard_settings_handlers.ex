defmodule IchorWeb.DashboardSettingsHandlers do
  @moduledoc """
  Handles settings page events.
  Each dispatch/3 clause returns the updated socket (caller wraps in {:noreply, ...}).
  """

  import Phoenix.Component, only: [assign: 3, to_form: 1]

  alias Ichor.Settings.SettingsProject

  def dispatch("settings_project_event", %{"action" => "new"} = _params, socket) do
    form =
      SettingsProject
      |> AshPhoenix.Form.for_create(:create, as: "settings_project", forms: [auto?: true])
      |> AshPhoenix.Form.add_form([:location])
      |> to_form()

    socket
    |> assign(:settings_project_form, form)
    |> assign(:browsed_path, nil)
  end

  def dispatch("settings_project_event", %{"action" => "edit", "id" => id}, socket) do
    project = Enum.find(socket.assigns.settings_projects, &(&1.id == id))

    form =
      project
      |> AshPhoenix.Form.for_update(:update, as: "settings_project")
      |> to_form()

    socket
    |> assign(:settings_project_form, form)
    |> assign(:browsed_path, nil)
  end

  def dispatch("settings_project_event", %{"action" => "validate"} = params, socket) do
    form =
      socket.assigns.settings_project_form.source
      |> AshPhoenix.Form.validate(params["settings_project"] || %{})
      |> to_form()

    assign(socket, :settings_project_form, form)
  end

  def dispatch("settings_project_event", %{"action" => "save"} = params, socket) do
    case AshPhoenix.Form.submit(socket.assigns.settings_project_form.source,
           params: params["settings_project"] || %{}
         ) do
      {:ok, _result} ->
        socket
        |> assign(:settings_project_form, nil)
        |> assign(:settings_projects, Ichor.Settings.list_settings_projects!())

      {:error, form} ->
        assign(socket, :settings_project_form, to_form(form))
    end
  end

  def dispatch("settings_project_event", %{"action" => "delete", "id" => id}, socket) do
    project = Enum.find(socket.assigns.settings_projects, &(&1.id == id))

    if project do
      Ichor.Settings.destroy_settings_project!(project)

      assign(socket, :settings_projects, Ichor.Settings.list_settings_projects!())
    else
      socket
    end
  end

  def dispatch("settings_project_event", %{"action" => "cancel"}, socket) do
    socket
    |> assign(:settings_project_form, nil)
    |> assign(:folder_browser, nil)
  end

  def dispatch("settings_project_event", %{"action" => "browse"}, socket) do
    home = System.user_home!()
    assign(socket, :folder_browser, list_dir(home))
  end

  def dispatch("settings_project_event", %{"action" => "browse_navigate", "path" => path}, socket) do
    assign(socket, :folder_browser, list_dir(path))
  end

  def dispatch("settings_project_event", %{"action" => "browse_select"}, socket) do
    socket
    |> assign(:browsed_path, socket.assigns.folder_browser.current)
    |> assign(:folder_browser, nil)
  end

  def dispatch(
        "settings_project_event",
        %{"action" => "browse_filter", "value" => filter},
        socket
      ) do
    browser = socket.assigns.folder_browser
    assign(socket, :folder_browser, %{browser | filter: filter})
  end

  def dispatch("settings_project_event", %{"action" => "browse_close"}, socket) do
    assign(socket, :folder_browser, nil)
  end

  def dispatch("select_settings_category", %{"category" => category}, socket) do
    assign(socket, :settings_category, String.to_existing_atom(category))
  end

  defp list_dir(path) do
    expanded = Path.expand(path)

    entries =
      case File.ls(expanded) do
        {:ok, names} ->
          names
          |> Enum.sort()
          |> Enum.filter(fn name ->
            full = Path.join(expanded, name)
            File.dir?(full) and not String.starts_with?(name, ".")
          end)

        {:error, _} ->
          []
      end

    breadcrumbs =
      expanded
      |> Path.split()
      |> Enum.reduce([], fn seg, acc ->
        parent = if acc == [], do: seg, else: Path.join(List.last(acc), seg)
        acc ++ [parent]
      end)

    %{current: expanded, entries: entries, breadcrumbs: breadcrumbs, filter: ""}
  end
end
