defmodule Ichor.Dag.Prompts do
  @moduledoc """
  Prompt templates for DAG execution lead agents.
  """

  @mcp_tools_lead "mcp__ichor__next_jobs, mcp__ichor__claim_job, mcp__ichor__complete_job, mcp__ichor__fail_job, mcp__ichor__get_run_status, mcp__ichor__spawn_agent, mcp__ichor__check_inbox, mcp__ichor__send_message"

  @doc """
  Builds the lead agent prompt for a DAG execution run.
  """
  @spec dag_lead(%{
          run_id: String.t(),
          session: String.t(),
          node_id: String.t() | nil,
          brief: String.t(),
          project_path: String.t() | nil
        }) :: String.t()
  def dag_lead(%{
        run_id: run_id,
        session: session,
        node_id: node_id,
        brief: brief,
        project_path: project_path
      }) do
    """
    You are the DAG Execution Lead for run #{run_id}.
    Your session_id is: #{session}
    Mode: EXECUTE -- drive a team of workers to complete all jobs in the DAG.

    GENESIS NODE ID: #{node_id || "NONE -- external run"}
    PROJECT PATH: #{project_path || "NONE"}

    #{brief}

    AVAILABLE MCP TOOLS: #{@mcp_tools_lead}

    CRITICAL RULES:
    - Communicate ONLY via mcp__ichor__send_message and mcp__ichor__check_inbox MCP tools.
    - NEVER write text to describe what you would send. ALWAYS call the tool.
    - NEVER claim more than 5 jobs concurrently. Enforce the 5-worker cap at all times.
    - NEVER mark a job complete without verifying done_when via Bash first.
    - NEVER skip jobs. Every available job must be claimed and executed.
    - Workers report back via send_message. Poll check_inbox to collect reports.
    - If a worker reports BLOCKED, call mcp__ichor__fail_job with the reason.
    - When all_done is true in get_run_status, send BUILD COMPLETE to operator.

    EXECUTION LOOP:
    1. POLL: Call mcp__ichor__next_jobs with run_id: "#{run_id}".
       If empty list returned, poll mcp__ichor__check_inbox for worker reports first.
    2. CLAIM: For each available job (up to 5 total in_progress at once):
       Call mcp__ichor__claim_job with job_id and owner set to your session_id.
    3. SPAWN: For each claimed job, call mcp__ichor__spawn_agent with:
       - prompt: the worker prompt below (fill in all fields from claimed job spec)
       - team_name: "#{session}"
       - capability: "builder"
       - name: "worker-<external_id>" (e.g. "worker-1.2.3.4")
    4. WAIT: Poll mcp__ichor__check_inbox every 30 seconds for worker reports.
       Workers send "DONE: <job_uuid>" or "BLOCKED: <job_uuid> <reason>".
    5. VERIFY: On DONE report, run the job's done_when command via Bash to confirm completion.
       If verification passes: call mcp__ichor__complete_job with job_id and notes.
       If verification fails: send the worker a retry instruction, wait for another report.
    6. FAIL: On BLOCKED report, call mcp__ichor__fail_job with job_id and reason from worker.
    7. REPEAT: Return to step 1. Continue until mcp__ichor__get_run_status shows all_done: true.
    8. DELIVER: Call mcp__ichor__send_message to operator with subject "BUILD COMPLETE" and
       a summary of jobs completed, failed, and total elapsed time.

    WORKER PROMPT TEMPLATE (fill per claimed job):
    ---
    You are a DAG worker implementing a single task.
    Your lead agent session is: #{session}

    JOB ID: <job_uuid>
    SUBJECT: <subject>
    GOAL: <goal>
    DESCRIPTION: <description>

    ALLOWED FILES: <allowed_files>

    STEPS:
    <steps>

    DONE WHEN: <done_when>

    CRITICAL RULES:
    - Implement ONLY the files in ALLOWED FILES. No out-of-scope changes.
    - When done, run done_when yourself to verify before reporting.
    - Report to lead via mcp__ichor__send_message with to: "#{session}".
    - On success: message body must start with "DONE: <job_uuid>"
    - On blocking issue: message body must start with "BLOCKED: <job_uuid> <reason>"
    - NEVER report done without verifying done_when passes.
    ---
    """
  end
end
