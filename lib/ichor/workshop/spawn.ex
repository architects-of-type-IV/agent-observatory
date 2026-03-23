defmodule Ichor.Workshop.Spawn do
  @moduledoc """
  Builds and launches a saved Workshop team definition by name.
  """

  alias Ichor.Infrastructure.AgentSpec
  alias Ichor.Infrastructure.TeamSpec
  alias Ichor.Signals
  alias Ichor.Workshop.{Presets, PromptProtocol, Team, TeamMember}

  @spawn_timeout 30_000

  @spec spawn_team(String.t()) :: {:ok, map()} | {:error, term()}
  def spawn_team(name) when is_binary(name) do
    case Team.by_name(name) do
      {:ok, team} ->
        with {:ok, members} <- TeamMember.for_team_with_type(team.id) do
          spawn_team(team, members)
        end

      {:error, _} ->
        spawn_preset(name)
    end
  end

  @spec spawn_team(Team.t()) :: {:ok, map()} | {:error, term()}
  def spawn_team(%Team{} = team) do
    case TeamMember.for_team_with_type(team.id) do
      {:ok, members} -> spawn_team(team, members)
      {:error, reason} -> {:error, reason}
    end
  end

  defp spawn_team(%Team{} = team, members) do
    spec = build_spec(team, members)
    request_spawn(spec, %{team_name: team.name, source: :team})
  end

  defp spawn_preset(name) do
    case Presets.fetch(name) do
      {:ok, preset} ->
        spec = build_preset_spec(name, preset)
        request_spawn(spec, %{team_name: name, source: :preset})

      :error ->
        {:error, {:team_not_found, name}}
    end
  end

  defp request_spawn(spec, extra_metadata) do
    request_id = Ecto.UUID.generate()
    do_request_spawn(request_id, spec, extra_metadata)
  end

  defp do_request_spawn(request_id, spec, extra_metadata) do
    :ok = Signals.subscribe(:team_spawn_ready, request_id)
    :ok = Signals.subscribe(:team_spawn_failed, request_id)

    Signals.emit(:team_spawn_requested, request_id, %{
      team_name: spec.team_name,
      spec: spec,
      source: Map.get(extra_metadata, :source, :team)
    })

    await_spawn_result(request_id, spec, extra_metadata)
  after
    Signals.unsubscribe(:team_spawn_ready, request_id)
    Signals.unsubscribe(:team_spawn_failed, request_id)
  end

  defp await_spawn_result(request_id, spec, extra_metadata) do
    receive do
      %Signals.Message{name: :team_spawn_ready, data: %{scope_id: ^request_id, session: session}} ->
        {:ok,
         %{
           team_name: spec.team_name,
           session: session,
           launched: length(spec.agents),
           total: length(spec.agents),
           members: Enum.map(spec.agents, &%{name: &1.name, agent_id: &1.agent_id})
         }
         |> Map.merge(extra_metadata)}

      %Signals.Message{
        name: :team_spawn_failed,
        data: %{scope_id: ^request_id, reason: reason}
      } ->
        {:error, reason}
    after
      @spawn_timeout ->
        {:error, :team_spawn_timeout}
    end
  end

  defp build_spec(%Team{} = team, members) do
    session = session_name(team.name)
    cwd = blank_to_cwd(team.cwd)
    links = team.spawn_links || []
    rules = team.comm_rules || []
    launch_agents = build_launch_agents(members)
    ordered_agents = Presets.spawn_order(launch_agents, links)

    TeamSpec.new(%{
      team_name: team.name,
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
            team_name: team.name,
            session: session,
            prompt: prompt_for_agent(agent, ordered_agents, rules, session, team.name),
            metadata: agent_metadata(agent, team.name)
          })
        end),
      prompt_dir: prompt_dir(team.name),
      metadata: %{
        source: :workshop,
        strategy: team.strategy,
        team_id: team.id
      }
    })
  end

  defp build_preset_spec(name, preset) do
    session = session_name(name)
    cwd = File.cwd!()
    links = Map.get(preset, :links, [])
    rules = Map.get(preset, :rules, [])

    agents =
      preset
      |> Map.get(:agents, [])
      |> Enum.map(fn agent ->
        %{
          id: agent.id,
          agent_type_id: nil,
          name: agent.name,
          capability: agent.capability,
          model: agent.model,
          permission: Map.get(agent, :permission, "default"),
          persona: Map.get(agent, :persona, ""),
          file_scope: Map.get(agent, :file_scope, ""),
          quality_gates: Map.get(agent, :quality_gates, ""),
          tools: Map.get(agent, :tools, [])
        }
      end)
      |> Presets.spawn_order(links)

    TeamSpec.new(%{
      team_name: name,
      session: session,
      cwd: cwd,
      agents:
        Enum.map(agents, fn agent ->
          AgentSpec.new(%{
            name: agent.name,
            window_name: window_name(agent),
            agent_id: "#{session}-#{window_name(agent)}",
            capability: agent.capability,
            model: agent.model,
            cwd: cwd,
            team_name: name,
            session: session,
            prompt: prompt_for_agent(agent, agents, rules, session, name),
            metadata: agent_metadata(agent, name)
          })
        end),
      prompt_dir: prompt_dir(name),
      metadata: %{
        source: :preset,
        preset_name: name,
        strategy: Map.get(preset, :strategy, "one_for_one")
      }
    })
  end

  defp build_launch_agents(members) do
    Enum.map(members, fn member ->
      type = member.agent_type

      %{
        id: member.slot,
        agent_type_id: member.agent_type_id,
        name: member.name,
        capability: member.capability,
        model: member.model,
        permission: member.permission,
        persona: effective_persona(type, member),
        file_scope: effective_file_scope(type, member),
        quality_gates: effective_quality_gates(type, member),
        tools: effective_tools(type, member)
      }
    end)
  end

  defp prompt_for_agent(agent, agents, rules, session, _team_name) do
    persona = Map.get(agent, :persona) || ""

    contacts =
      PromptProtocol.allowed_contacts(
        agent.id,
        rules,
        agents,
        session,
        PromptProtocol.extra_contacts_for(agent)
      )

    vars = %{
      "session" => session,
      "agent_name" => agent.name,
      "agent_session_id" => session_id_for(session, agent),
      "critical_rules" => PromptProtocol.critical_rules(""),
      "allowed_contacts" => contacts
    }

    PromptProtocol.render_template(persona, vars)
  end

  defp agent_metadata(agent, team_name) do
    %{
      source: :workshop,
      team_name: team_name,
      permission: agent.permission,
      file_scope: agent.file_scope,
      quality_gates: agent.quality_gates,
      tools: Map.get(agent, :tools, []),
      agent_type_id: agent[:agent_type_id]
    }
  end

  defp effective_persona(nil, member), do: member.extra_instructions

  defp effective_persona(type, member) do
    [type.default_persona || "", member.extra_instructions || ""]
    |> Enum.reject(&(&1 == ""))
    |> Enum.join("\n\n")
  end

  defp effective_file_scope(nil, member), do: member.file_scope

  defp effective_file_scope(type, member),
    do: first_present(member.file_scope, type.default_file_scope)

  defp effective_quality_gates(nil, member), do: member.quality_gates

  defp effective_quality_gates(type, member),
    do: first_present(member.quality_gates, type.default_quality_gates)

  defp effective_tools(nil, member), do: member.tool_scope || []

  defp effective_tools(type, member) do
    first_present(member.tool_scope || [], type.default_tools || [])
  end

  defp first_present("", fallback), do: fallback || ""
  defp first_present(nil, fallback), do: fallback || ""
  defp first_present([], fallback), do: fallback
  defp first_present(value, _fallback), do: value

  defp blank_to_cwd(""), do: File.cwd!()
  defp blank_to_cwd(nil), do: File.cwd!()
  defp blank_to_cwd(value), do: value

  defp session_name(team_name), do: "workshop-#{slug(team_name)}"
  defp prompt_dir(team_name), do: Path.join(prompt_root_dir(), slug(team_name))

  defp prompt_root_dir do
    Application.get_env(:ichor, :workshop_prompt_root_dir, Path.expand("~/.ichor/workshop"))
  end

  defp session_id_for(session, agent), do: "#{session}-#{window_name(agent)}"
  defp window_name(agent), do: slug("#{agent.id}-#{agent.name}")

  defp slug(value) do
    value
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/u, "-")
    |> String.trim("-")
  end
end
