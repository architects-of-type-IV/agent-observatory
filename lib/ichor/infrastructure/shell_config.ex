defmodule Ichor.Infrastructure.ShellConfig do
  @moduledoc """
  Manages the ICHOR shell environment for tmux sessions.

  Generates a minimal `.zshrc` with a branded prompt so sessions launched
  by ICHOR have a clean, consistent look instead of the user's personal
  shell theme. Config lives in the ICHOR data directory (`~/.ichor/shell/`).

  ## Usage

      # Get tmux env args to redirect zsh config
      ShellConfig.env_args()
      #=> ["-e", "ZDOTDIR=/Users/x/.ichor/shell"]

      # Ensure config exists before launching
      ShellConfig.ensure()

  ## Prompt

  Default prompt: muted path with green/red status indicator.

      ~/code/observatory >

  Override via `write_config/1` or reset with `reset/0`.
  """

  @doc "Root directory for shell config (ZDOTDIR target)."
  @spec data_dir() :: String.t()
  def data_dir, do: Path.expand("~/.ichor/shell")

  @doc "Returns tmux `-e` args to set ZDOTDIR for branded shell."
  @spec env_args() :: [String.t()]
  def env_args, do: ["-e", "ZDOTDIR=#{data_dir()}"]

  @doc """
  Ensure the shell config directory and `.zshrc` exist.
  Idempotent -- only writes if the file is missing.
  """
  @spec ensure() :: :ok
  def ensure do
    dir = data_dir()
    File.mkdir_p!(dir)
    zshrc = Path.join(dir, ".zshrc")

    unless File.exists?(zshrc) do
      File.write!(zshrc, default_zshrc())
    end

    :ok
  end

  @doc "Write a custom `.zshrc` to the shell config directory."
  @spec write_config(String.t()) :: :ok
  def write_config(content) when is_binary(content) do
    dir = data_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".zshrc"), content)
    :ok
  end

  @doc "Reset the shell config to the default branded prompt."
  @spec reset() :: :ok
  def reset do
    dir = data_dir()
    File.mkdir_p!(dir)
    File.write!(Path.join(dir, ".zshrc"), default_zshrc())
    :ok
  end

  @doc "Read the current shell config content."
  @spec read() :: {:ok, String.t()} | {:error, File.posix()}
  def read, do: File.read(Path.join(data_dir(), ".zshrc"))

  defp default_zshrc do
    """
    # ICHOR IV -- managed shell config
    # Override via ShellConfig.write_config/1 or reset via the UI.

    PS1='%F{242}%~%f %(?.%F{green}.%F{red})>%f '

    export CLICOLOR=1
    export EDITOR=vim

    HISTSIZE=1000
    SAVEHIST=1000
    HISTFILE="${ZDOTDIR}/.zsh_history"
    setopt HIST_IGNORE_DUPS
    """
  end
end
