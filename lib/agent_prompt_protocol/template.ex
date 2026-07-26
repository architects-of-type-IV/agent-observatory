defmodule AgentPromptProtocol.Template do
  @moduledoc """
  `{{var}}` substitution for prompt templates.

  Deliberately minimal: no conditionals, no loops, no partials. A prompt
  template that needs control flow is a sign the logic belongs in the code that
  assembles it, where it can be tested.

  ## Missing variables

  The default is to leave an unresolved `{{var}}` in place and log a warning.
  That is the right default for prompts — a half-rendered prompt that visibly
  contains `{{run_id}}` is diagnosable from the agent's transcript, whereas one
  that silently dropped the value looks fine and behaves strangely.

  Use `:on_missing` to choose otherwise:

      render(template, vars)                        # keep, and warn
      render(template, vars, on_missing: :empty)    # drop silently
      render(template, vars, on_missing: :raise)    # fail loudly
      render(template, vars, on_missing: :keep_quiet)

  Or check first with `unresolved/1` and decide.
  """

  require Logger

  @pattern ~r/\{\{(\w+)\}\}/

  @doc """
  Render `{{var}}` placeholders from a map of string keys.

      iex> AgentPromptProtocol.Template.render("Hello {{name}}", %{"name" => "Ada"})
      "Hello Ada"

  An empty template renders to an empty string without touching `vars`.

      iex> AgentPromptProtocol.Template.render("", %{})
      ""

  ## Options

    * `:on_missing` — `:keep` (default, warns), `:keep_quiet`, `:empty`, or `:raise`
  """
  @spec render(String.t(), %{optional(String.t()) => term()}, keyword()) :: String.t()
  def render(template, vars, opts \\ [])

  def render("", _vars, _opts), do: ""

  def render(template, vars, opts) when is_binary(template) and is_map(vars) do
    on_missing = Keyword.get(opts, :on_missing, :keep)

    rendered =
      Regex.replace(@pattern, template, fn _match, key ->
        case Map.fetch(vars, key) do
          {:ok, value} -> to_string(value)
          :error -> missing(key, on_missing)
        end
      end)

    warn_unresolved(rendered, on_missing)
    rendered
  end

  @doc """
  The distinct variable names a template references, in order of first use.

      iex> AgentPromptProtocol.Template.variables("{{a}} then {{b}} then {{a}}")
      ["a", "b"]
  """
  @spec variables(String.t()) :: [String.t()]
  def variables(template) when is_binary(template) do
    @pattern
    |> Regex.scan(template)
    |> Enum.map(fn [_full, key] -> key end)
    |> Enum.uniq()
  end

  @doc """
  Variables a template references that `vars` does not supply.

      iex> AgentPromptProtocol.Template.unresolved("{{a}} {{b}}", %{"a" => 1})
      ["b"]

  Use this to validate a prompt before spawning an agent, rather than
  discovering the gap in the transcript afterwards.
  """
  @spec unresolved(String.t(), %{optional(String.t()) => term()}) :: [String.t()]
  def unresolved(template, vars \\ %{}) when is_binary(template) and is_map(vars) do
    template
    |> variables()
    |> Enum.reject(&Map.has_key?(vars, &1))
  end

  defp missing(key, :raise), do: raise(KeyError, key: key, term: "prompt template")
  defp missing(_key, :empty), do: ""
  defp missing(key, _keep), do: "{{#{key}}}"

  defp warn_unresolved(rendered, on_missing) when on_missing in [:keep, nil] do
    case variables(rendered) do
      [] -> :ok
      keys -> Logger.warning("AgentPromptProtocol.Template: unresolved vars #{inspect(keys)}")
    end
  end

  defp warn_unresolved(_rendered, _on_missing), do: :ok
end
