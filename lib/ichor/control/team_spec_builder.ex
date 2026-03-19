defmodule Ichor.Control.TeamSpecBuilder do
  @moduledoc """
  Builds lifecycle `TeamSpec` and `AgentSpec` values from Workshop state.
  """

  alias Ichor.Control.Lifecycle.AgentSpec
  alias Ichor.Control.Lifecycle.TeamSpec
  alias Ichor.Control.Presets

  @doc "Build a `TeamSpec` from workshop LiveView state and optional overrides."
  @spec build_from_state(map(), keyword()) :: TeamSpec.t()
  def build_from_state(state, opts \\ []) do
    team_name = state.ws_team_name
    session = Keyword.get(opts, :session, session_name(team_name))
    cwd = state.ws_cwd |> blank_to_cwd()
    ordered_agents = Presets.spawn_order(state.ws_agents, state.ws_spawn_links)
    prompt_builder = Keyword.get(opts, :prompt_builder, &prompt_for_agent/2)
    agent_metadata_builder = Keyword.get(opts, :agent_metadata_builder, &default_agent_metadata/2)
    window_name_builder = Keyword.get(opts, :window_name_builder, &window_name/1)

    agent_id_builder =
      Keyword.get(opts, :agent_id_builder, fn _agent, built_window_name, built_session ->
        "#{built_session}-#{built_window_name}"
      end)

    TeamSpec.new(%{
      team_name: team_name,
      session: session,
      cwd: cwd,
      agents:
        Enum.map(ordered_agents, fn agent ->
          built_window_name = window_name_builder.(agent)

          AgentSpec.new(%{
            name: agent.name,
            window_name: built_window_name,
            agent_id: agent_id_builder.(agent, built_window_name, session),
            capability: agent.capability,
            model: agent.model,
            cwd: cwd,
            team_name: team_name,
            session: session,
            prompt: prompt_builder.(agent, state),
            metadata: agent_metadata_builder.(agent, state)
          })
        end),
      prompt_dir: Keyword.get(opts, :prompt_dir, prompt_dir(team_name)),
      metadata:
        Keyword.get(opts, :team_metadata, %{
          source: :workshop,
          strategy: state.ws_strategy,
          blueprint_id: state[:ws_blueprint_id]
        })
    })
  end

  @doc "Derive the tmux session name from a team name."
  @spec session_name(String.t()) :: String.t()
  def session_name(team_name), do: "workshop-#{slug(team_name)}"

  @doc "Return the prompt directory path for a team."
  @spec prompt_dir(String.t()) :: String.t()
  def prompt_dir(team_name), do: Path.join(prompt_root_dir(), slug(team_name))

  @doc "Return the root prompt directory, from config or default."
  @spec prompt_root_dir() :: String.t()
  def prompt_root_dir do
    Application.get_env(:ichor, :workshop_prompt_root_dir, Path.expand("~/.ichor/workshop"))
  end

  defp prompt_for_agent(agent, state) do
    spawn_context =
      state.ws_spawn_links
      |> Enum.filter(&(&1.from == agent.id))
      |> Enum.map(fn link -> "Spawn child slot #{link.to}" end)

    comm_context =
      state.ws_comm_rules
      |> Enum.filter(&(&1.from == agent.id))
      |> Enum.map(fn rule ->
        via =
          case rule.via do
            nil -> ""
            value -> " via slot #{value}"
          end

        "Communication to slot #{rule.to}: #{rule.policy}#{via}"
      end)

    [
      "You are #{agent.name}, a #{agent.capability} agent in workshop team #{state.ws_team_name}.",
      blank_line_if_present(agent.persona),
      optional_line("Permission profile: #{agent.permission}", agent.permission),
      optional_line("File scope: #{agent.file_scope}", agent.file_scope),
      optional_line("Quality gates: #{agent.quality_gates}", agent.quality_gates),
      list_block("Spawn responsibilities", spawn_context),
      list_block("Communication rules", comm_context)
    ]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join("\n\n")
  end

  defp default_agent_metadata(agent, state) do
    %{
      source: :workshop,
      team_name: state.ws_team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates
    }
  end

  defp list_block(_title, []), do: nil

  defp list_block(title, items) do
    [title <> ":", Enum.map_join(items, "\n", &"- #{&1}")]
    |> Enum.join("\n")
  end

  defp blank_line_if_present(""), do: nil
  defp blank_line_if_present(nil), do: nil
  defp blank_line_if_present(value), do: value

  defp optional_line(_label, ""), do: nil
  defp optional_line(_label, nil), do: nil
  defp optional_line(label, _value), do: label

  defp blank_to_cwd(""), do: File.cwd!()
  defp blank_to_cwd(nil), do: File.cwd!()
  defp blank_to_cwd(value), do: value

  defp window_name(agent), do: slug("#{agent.id}-#{agent.name}")

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
