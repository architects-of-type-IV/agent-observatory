defmodule Ichor.Mes.TeamSpecBuilder do
  @moduledoc """
  Pure builder for MES `TeamSpec` and `AgentSpec` runtime contracts.
  """

  alias Ichor.Fleet.Lifecycle.AgentSpec
  alias Ichor.Fleet.Lifecycle.TeamSpec
  alias Ichor.Mes.TeamPrompts

  @spec build_team_spec(String.t(), String.t()) :: TeamSpec.t()
  def build_team_spec(run_id, team_name) do
    cwd = project_root()
    session = session_name(run_id)
    roster = TeamPrompts.roster(session)

    TeamSpec.new(%{
      team_name: team_name,
      session: session,
      cwd: cwd,
      agents: [
        build_agent_spec(
          "coordinator",
          "coordinator",
          TeamPrompts.coordinator(run_id, roster),
          cwd,
          session,
          team_name,
          run_id
        ),
        build_agent_spec(
          "lead",
          "lead",
          TeamPrompts.lead(run_id, roster),
          cwd,
          session,
          team_name,
          run_id
        ),
        build_agent_spec(
          "planner",
          "builder",
          TeamPrompts.planner(run_id, roster),
          cwd,
          session,
          team_name,
          run_id
        ),
        build_agent_spec(
          "researcher-1",
          "scout",
          TeamPrompts.researcher_1(run_id, roster),
          cwd,
          session,
          team_name,
          run_id
        ),
        build_agent_spec(
          "researcher-2",
          "scout",
          TeamPrompts.researcher_2(run_id, roster),
          cwd,
          session,
          team_name,
          run_id
        )
      ],
      prompt_dir: prompt_dir(run_id),
      metadata: %{run_id: run_id}
    })
  end

  @spec build_corrective_team_spec(String.t(), String.t(), String.t() | nil, pos_integer()) ::
          TeamSpec.t()
  def build_corrective_team_spec(run_id, session, reason, attempt) do
    cwd = project_root()
    name = "corrective-#{attempt}"

    TeamSpec.new(%{
      team_name: session_name(run_id),
      session: session,
      cwd: cwd,
      agents: [
        AgentSpec.new(%{
          name: name,
          window_name: name,
          agent_id: "#{session}-#{name}",
          capability: "builder",
          model: "sonnet",
          cwd: cwd,
          team_name: session_name(run_id),
          session: session,
          prompt: TeamPrompts.corrective(run_id, session, reason),
          metadata: %{run_id: run_id}
        })
      ],
      prompt_dir: prompt_dir(run_id),
      metadata: %{run_id: run_id}
    })
  end

  @spec session_name(String.t()) :: String.t()
  def session_name(run_id), do: "mes-#{run_id}"

  @spec prompt_dir(String.t()) :: String.t()
  def prompt_dir(run_id), do: Path.join(prompt_root_dir(), run_id)

  @spec prompt_root_dir() :: String.t()
  def prompt_root_dir do
    Application.get_env(:ichor, :mes_prompt_root_dir, Path.expand("~/.ichor/mes"))
  end

  defp project_root, do: File.cwd!()

  defp build_agent_spec(name, capability, prompt, cwd, session, team_name, run_id) do
    AgentSpec.new(%{
      name: name,
      window_name: name,
      agent_id: "#{session}-#{name}",
      capability: capability,
      model: "sonnet",
      cwd: cwd,
      team_name: team_name,
      session: session,
      prompt: prompt,
      metadata: %{run_id: run_id}
    })
  end
end
