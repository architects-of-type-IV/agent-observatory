defmodule Signals.Topic do
  import Kernel, except: [match?: 2]

  @moduledoc """
  Matching topic patterns against event types.

  A signal declares the topics it watches. That declaration is the interesting
  part of a signal — it is the claim about which unrelated events are worth
  considering together — so it is data, inspectable, rather than logic buried in
  a predicate.

  ## Patterns

  | Pattern | Matches |
  |---|---|
  | `"agent.tool.completed"` | exactly that type |
  | `"agent.*"` | any type under `agent.`, at any depth |
  | `"signal.*"` | every signal emission — how meta-signals subscribe |
  | `"*"` | everything |

  `*` is a trailing wildcard covering one *or more* remaining segments, so
  `"agent.*"` matches `agent.crashed` and `agent.tool.completed` alike. That
  matches how the topic tables are written, where `agent.*` means "the agent
  family" rather than "agent plus exactly one segment".
  """

  @doc """
  Whether a type matches a pattern.

      iex> Signals.Topic.match?("agent.tool.completed", "agent.tool.completed")
      true
      iex> Signals.Topic.match?("agent.tool.completed", "agent.*")
      true
      iex> Signals.Topic.match?("agent.crashed", "agent.*")
      true
      iex> Signals.Topic.match?("agents.crashed", "agent.*")
      false
      iex> Signals.Topic.match?("anything.at.all", "*")
      true
  """
  @spec match?(String.t(), String.t()) :: boolean()
  def match?(type, "*") when is_binary(type), do: true

  def match?(type, pattern) when is_binary(type) and is_binary(pattern) do
    case String.split(pattern, ".*", parts: 2) do
      [^pattern] -> type == pattern
      [prefix, ""] -> String.starts_with?(type, prefix <> ".")
      _ -> type == pattern
    end
  end

  def match?(_type, _pattern), do: false

  @doc """
  Whether a type matches any pattern in a list.

      iex> Signals.Topic.matches_any?("agent.crashed", ["pipeline.*", "agent.*"])
      true
      iex> Signals.Topic.matches_any?("system.started", ["agent.*"])
      false
  """
  @spec matches_any?(String.t(), [String.t()]) :: boolean()
  def matches_any?(type, patterns) when is_list(patterns),
    do: Enum.any?(patterns, &match?(type, &1))

  def matches_any?(_type, _patterns), do: false

  @doc """
  The topic a signal's emissions are published under.

      iex> Signals.Topic.emission_type("loop_detected")
      "signal.loop_detected"
  """
  @spec emission_type(String.t() | atom()) :: String.t()
  def emission_type(name), do: Signals.Config.emission_prefix() <> to_string(name)

  @doc """
  Whether a pattern would subscribe a signal to other signals' emissions.

  Useful for detecting meta-signals when rendering the subscription graph.

      iex> Signals.Topic.meta?(["signal.*"])
      true
      iex> Signals.Topic.meta?(["agent.*"])
      false
  """
  @spec meta?([String.t()]) :: boolean()
  def meta?(patterns) when is_list(patterns) do
    prefix = Signals.Config.emission_prefix()
    Enum.any?(patterns, &(&1 == "*" or String.starts_with?(&1, prefix)))
  end

  def meta?(_), do: false
end
