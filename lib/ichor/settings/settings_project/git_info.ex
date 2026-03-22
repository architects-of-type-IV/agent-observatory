defmodule Ichor.Settings.SettingsProject.GitInfo do
  @moduledoc """
  Ash change that detects git repo info from a project's local path.

  When the location path contains a `.git` folder, extracts the remote URL
  and derives the repo name (org/project format).
  """

  use Ash.Resource.Change

  @impl true
  def change(changeset, _opts, _context) do
    case get_local_path(changeset) do
      nil -> changeset
      path -> maybe_set_git_info(changeset, path)
    end
  end

  defp get_local_path(changeset) do
    case Ash.Changeset.get_attribute(changeset, :location) do
      %{type: :local, path: path} when is_binary(path) and path != "" -> path
      %{"type" => "local", "path" => path} when is_binary(path) and path != "" -> path
      _ -> nil
    end
  end

  defp maybe_set_git_info(changeset, path) do
    git_dir = Path.join(path, ".git")

    if File.dir?(git_dir) do
      {url, name} = read_git_remote(path)

      changeset
      |> Ash.Changeset.force_change_attribute(:repo_url, url)
      |> Ash.Changeset.force_change_attribute(:repo_name, name)
    else
      changeset
    end
  end

  defp read_git_remote(path) do
    case System.cmd("git", ["-C", path, "remote", "get-url", "origin"], stderr_to_stdout: true) do
      {url, 0} ->
        url = String.trim(url)
        {url, extract_repo_name(url)}

      _ ->
        {nil, nil}
    end
  end

  defp extract_repo_name(url) do
    url
    |> String.replace(~r/\.git$/, "")
    |> then(fn cleaned ->
      cond do
        # HTTPS: https://github.com/org/repo
        String.contains?(cleaned, "://") ->
          cleaned |> URI.parse() |> Map.get(:path, "") |> String.trim_leading("/")

        # SSH: git@github.com:org/repo
        String.contains?(cleaned, ":") ->
          cleaned |> String.split(":") |> List.last()

        true ->
          nil
      end
    end)
  end
end
