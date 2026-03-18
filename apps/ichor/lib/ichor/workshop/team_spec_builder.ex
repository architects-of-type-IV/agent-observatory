defmodule Ichor.Workshop.TeamSpecBuilder do
  @moduledoc """
  Builds lifecycle `TeamSpec` and `AgentSpec` values from Workshop state.
  """

  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.Lifecycle.TeamSpec
  alias Ichor.Workshop.Presets

  @spec build_from_state(map()) :: TeamSpec.t()
  def build_from_state(state) do
    team_name = state.ws_team_name
    session = session_name(team_name)
    cwd = state.ws_cwd |> blank_to_cwd()
    ordered_agents = Presets.spawn_order(state.ws_agents, state.ws_spawn_links)

    TeamSpec.new(%{
      team_name: team_name,
      session: session,
      cwd: cwd,
      agents:
        Enum.map(ordered_agents, fn agent ->
          AgentSpec.new(%{
            name: agent.name,
            window_name: window_name(agent),
            agent_id: "#{session}-#{window_name(agent)}",
            capability: agent.capability,
            model: agent.model,
            cwd: cwd,
            team_name: team_name,
            session: session,
            prompt: prompt_for_agent(agent, state),
            metadata: %{
              source: :workshop,
              team_name: team_name,
              permission: agent.permission,
              file_scope: agent.file_scope,
              quality_gates: agent.quality_gates
            }
          })
        end),
      prompt_dir: prompt_dir(team_name),
      metadata: %{
        source: :workshop,
        strategy: state.ws_strategy,
        blueprint_id: state[:ws_blueprint_id]
      }
    })
  end

  @spec session_name(String.t()) :: String.t()
  def session_name(team_name), do: "workshop-#{slug(team_name)}"

  @spec prompt_dir(String.t()) :: String.t()
  def prompt_dir(team_name), do: Path.join(prompt_root_dir(), slug(team_name))

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
