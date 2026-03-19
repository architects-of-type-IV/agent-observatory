defmodule Ichor.Control do
  @moduledoc """
  Ash Domain: Agent control plane.

  Manages agents, their configurations, spawning, and coordination.
  Fleet is all agents. Teams are agents with the same group name.
  Blueprints are agent configurations with instructions.
  """
  use Ash.Domain

  alias Ichor.Fleet.Agent
  alias Ichor.Fleet.Team
  alias Ichor.Workshop.AgentType
  alias Ichor.Workshop.TeamBlueprint

  resources do
    resource(Ichor.Fleet.Agent)
    resource(Ichor.Fleet.Team)
    resource(Ichor.Workshop.TeamBlueprint)
    resource(Ichor.Workshop.AgentBlueprint)
    resource(Ichor.Workshop.AgentType)
    resource(Ichor.Workshop.SpawnLink)
    resource(Ichor.Workshop.CommRule)
    resource(Ichor.Gateway.WebhookDelivery)
    resource(Ichor.Gateway.CronJob)
  end

  @doc "Returns all registered agents."
  @spec list_agents() :: list(Agent.t())
  def list_agents, do: Agent.all!()

  @doc "Returns agents in :active status."
  @spec list_active_agents() :: list(Agent.t())
  def list_active_agents, do: Agent.active!()

  @doc "Returns teams that are currently alive."
  @spec list_alive_teams() :: list(Team.t())
  def list_alive_teams, do: Team.alive!()

  @doc "Returns all registered teams."
  @spec list_teams() :: list(Team.t())
  def list_teams, do: Team.all!()

  @doc "Returns unread messages for the given agent."
  @spec get_unread(String.t()) :: {:ok, list(map())}
  def get_unread(agent_id), do: Agent.get_unread(agent_id)

  @doc "Marks a specific message as read for the given agent."
  @spec mark_read(String.t(), String.t()) :: {:ok, map()}
  def mark_read(agent_id, message_id), do: Agent.mark_read(agent_id, message_id)

  @doc "Returns all blueprints with agent_blueprints, spawn_links, and comm_rules loaded."
  @spec list_blueprints() :: [TeamBlueprint.t()]
  def list_blueprints do
    TeamBlueprint.read!(load: [:agent_blueprints, :spawn_links, :comm_rules])
  end

  @doc "Returns all agent types sorted by sort_order asc, name asc."
  @spec list_agent_types() :: [AgentType.t()]
  def list_agent_types, do: AgentType.sorted!()

  @doc "Fetches a single blueprint by id with relationships loaded."
  @spec blueprint_by_id(String.t()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_id(id), do: TeamBlueprint.by_id(id)

  @doc "Fetches a single blueprint by name with relationships loaded."
  @spec blueprint_by_name(String.t()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def blueprint_by_name(name), do: TeamBlueprint.by_name(name)

  @doc "Creates a blueprint from the given attrs map."
  @spec create_blueprint(map()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def create_blueprint(attrs), do: TeamBlueprint.create(attrs)

  @doc "Updates an existing blueprint with the given attrs map."
  @spec update_blueprint(TeamBlueprint.t(), map()) :: {:ok, TeamBlueprint.t()} | {:error, term()}
  def update_blueprint(blueprint, attrs), do: TeamBlueprint.update(blueprint, attrs)

  @doc "Destroys a blueprint record."
  @spec destroy_blueprint(TeamBlueprint.t()) :: :ok | {:error, term()}
  def destroy_blueprint(blueprint), do: TeamBlueprint.destroy(blueprint)

  @doc "Returns a single agent type by id."
  @spec agent_type(String.t()) :: {:ok, AgentType.t()} | {:error, term()}
  def agent_type(id), do: AgentType.by_id(id)

  @doc "Creates an agent type from the given attrs map."
  @spec create_agent_type(map()) :: {:ok, AgentType.t()} | {:error, term()}
  def create_agent_type(attrs), do: AgentType.create(attrs)

  @doc "Updates an existing agent type with the given attrs map."
  @spec update_agent_type(AgentType.t(), map()) :: {:ok, AgentType.t()} | {:error, term()}
  def update_agent_type(agent_type, attrs), do: AgentType.update(agent_type, attrs)

  @doc "Destroys an agent type record."
  @spec destroy_agent_type(AgentType.t()) :: :ok | {:error, term()}
  def destroy_agent_type(agent_type), do: AgentType.destroy(agent_type)

  alias Ichor.Gateway.WebhookDelivery

  @doc "Enqueues a webhook delivery for the given agent and target."
  @spec enqueue_webhook_delivery(map()) :: {:ok, WebhookDelivery.t()} | {:error, term()}
  def enqueue_webhook_delivery(
        %{target_url: target_url, payload: payload, signature: signature, agent_id: agent_id} =
          attrs
      ) do
    WebhookDelivery.enqueue(target_url, payload, signature, agent_id,
      webhook_id: Map.get(attrs, :webhook_id)
    )
  end

  @doc "Returns webhook deliveries that are due for immediate delivery."
  @spec list_due_webhook_deliveries() :: [WebhookDelivery.t()]
  def list_due_webhook_deliveries, do: WebhookDelivery.due_for_delivery!()

  @doc "Returns dead-letter webhook deliveries for the given agent."
  @spec list_dead_letters_for_agent(String.t()) :: [WebhookDelivery.t()]
  def list_dead_letters_for_agent(agent_id), do: WebhookDelivery.dead_letters_for_agent!(agent_id)

  @doc "Returns all dead-letter webhook deliveries across all agents."
  @spec list_all_dead_letters() :: [WebhookDelivery.t()]
  def list_all_dead_letters, do: WebhookDelivery.all_dead_letters!()

  @doc "Marks a webhook delivery as successfully delivered."
  @spec mark_webhook_delivered(WebhookDelivery.t()) ::
          {:ok, WebhookDelivery.t()} | {:error, term()}
  def mark_webhook_delivered(delivery), do: WebhookDelivery.mark_delivered(delivery)

  @doc "Schedules a retry for a failed webhook delivery."
  @spec schedule_webhook_retry(WebhookDelivery.t(), map()) ::
          {:ok, WebhookDelivery.t()} | {:error, term()}
  def schedule_webhook_retry(delivery, attrs), do: WebhookDelivery.schedule_retry(delivery, attrs)

  @doc "Moves a webhook delivery to the dead-letter queue."
  @spec mark_webhook_dead(WebhookDelivery.t(), map()) ::
          {:ok, WebhookDelivery.t()} | {:error, term()}
  def mark_webhook_dead(delivery, attrs \\ %{}), do: WebhookDelivery.mark_dead(delivery, attrs)

  alias Ichor.Gateway.CronJob

  @doc "Schedules a one-time cron job for the given agent."
  @spec schedule_cron_once(String.t(), String.t(), DateTime.t()) ::
          {:ok, CronJob.t()} | {:error, term()}
  def schedule_cron_once(agent_id, payload, next_fire_at),
    do: CronJob.schedule_once(agent_id, payload, next_fire_at)

  @doc "Returns all cron jobs for the given agent."
  @spec list_cron_jobs_for_agent(String.t()) :: [CronJob.t()]
  def list_cron_jobs_for_agent(agent_id), do: CronJob.for_agent!(agent_id)

  @doc "Returns all scheduled cron jobs sorted by next_fire_at asc."
  @spec list_all_cron_jobs() :: [CronJob.t()]
  def list_all_cron_jobs, do: CronJob.all_scheduled!()

  @doc "Returns cron jobs due at or before the given datetime."
  @spec list_due_cron_jobs(DateTime.t()) :: [CronJob.t()]
  def list_due_cron_jobs(now), do: CronJob.due!(now)

  @doc "Fetches a single cron job by id."
  @spec get_cron_job(String.t()) :: {:ok, CronJob.t()} | {:error, term()}
  def get_cron_job(id), do: CronJob.get(id)

  @doc "Reschedules a cron job to the given datetime."
  @spec reschedule_cron_job(CronJob.t(), DateTime.t()) :: {:ok, CronJob.t()} | {:error, term()}
  def reschedule_cron_job(job, next_fire_at), do: CronJob.reschedule(job, next_fire_at)

  @doc "Completes (destroys) a cron job after firing."
  @spec complete_cron_job(CronJob.t()) :: :ok | {:error, term()}
  def complete_cron_job(job), do: CronJob.complete(job)
end
