# Dynamic Agents with tmux Sessions

Research notes extracted from mobile screenshots (2026-03-22, 01:39 - 03:21).

---

## Part 1: Sandbox Plugins on the BEAM

**Can you sandbox plugins on the BEAM?**

Strictly speaking, no. Code running on the BEAM has nearly unlimited access to the VM's state and the host system. However, you can achieve "soft sandboxing" using these methods:

- **Luerl (Lua on BEAM):** The Sandbox and Luerl libraries allow you to execute Lua scripts within Elixir. Since Lua is interpreted as a data structure by the BEAM, it can be strictly limited in terms of CPU cycles (reductions) and memory.

- **Dune:** The Dune library provides a restricted subset of Elixir for safely evaluating user-provided code. It prevents common "escapes" like atom leaks or unauthorized module creation.

- **WebAssembly (WASM):** Use Wasmex to run compiled WASM modules. This provides the strongest isolation, as WASM is designed for secure, sandboxed execution with explicit memory boundaries.

---

## Part 2: Fail-Soft Strategies for Plugins

1. **Isolated Supervision Trees:** Run each plugin in its own supervision tree under a `DynamicSupervisor`. If a plugin crashes, only its specific tree is affected and can be restarted or shut down without impacting the host.

2. **Circuit Breakers:** Use a library like `fuse` to monitor plugin health. If a plugin fails repeatedly (e.g., 5 times in 10 seconds), the circuit "trips," and the system stops calling that plugin until it is manually reset or fixed.

3. **Validation on Load:** Before fully registering a plugin, run a "smoke test" or validation suite against it in a temporary process. Only register it if it passes these basic health checks.

4. **Signal vs. Exception:** Prefer using return tuples like `{:error, reason}` for expected plugin failures rather than letting them `raise` exceptions, which can be more expensive to recover from.

---

## Part 3: Define the Agent

Create a module that uses `Agent`. It is best practice to define a `start_link/1` function that the supervisor will call.

```elixir
defmodule MyAgent do
  use Agent, restart: :temporary # Use :temporary if the agent should just
                                 # disappear upon finishing its work or crashing.

  def start_link(initial_value) do
    Agent.start_link(fn -> initial_value end)
  end
end
```

---

## Part 4: Configure the DynamicSupervisor

Add the `DynamicSupervisor` to your application's supervision tree (typically in `lib/my_app/application.ex`).

```elixir
children = [
  {DynamicSupervisor, name: MyApp.DynamicSupervisor}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

---

## Part 5: Load Agents Dynamically

Use `start_child/2` to add an agent instance at runtime. This happens immediately without requiring any restarts of the supervisor or the application.

```elixir
# Start an agent with an initial state
{:ok, agent_pid} = DynamicSupervisor.start_child(
  MyApp.DynamicSupervisor,
  {MyAgent, initial_value}
)

# You can now interact with this agent
Agent.get(agent_pid, & &1)
```

### Key Considerations

- **Restart Strategy:** If an Agent crashes and you want the supervisor to restart it automatically, ensure your Agent's child specification uses `restart: :permanent` (default) or `:transient`. Use `:temporary` if the agent should just disappear upon finishing its work or crashing.

- **Identification:** Since dynamic agents are often started without names, you should store their PIDs or use a `Registry` if you need to look them up by a unique key later.

- **Scaling:** Because the supervisor is already running in your tree, you can call `start_child` hundreds or thousands of times to handle spikes in load without affecting other parts of the system.

---

## Part 6: Starting Agents in a Running Application

To start Agents in a running Elixir application without a restart, you must use a `DynamicSupervisor`. Unlike standard supervisors that require a predefined list of children at startup, a `DynamicSupervisor` is designed to have workers added or removed at any time during the application's lifecycle.

### Step-by-Step Implementation

#### 1. Ensure a DynamicSupervisor is Running

Your application must already have a `DynamicSupervisor` in its supervision tree. If it doesn't, you must add it once and deploy that change; from then on, you can add agents dynamically without further restarts.

```elixir
# In lib/my_app/application.ex
children = [
  {DynamicSupervisor, name: MyApp.AgentSupervisor}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

#### 2. Define Your Agent Module

Define the agent you want to run. It should implement a `start_link/1` function to be compatible with the supervisor.

```elixir
defmodule MyApp.MyAgent do
  use Agent

  def start_link(initial_state), do:
    Agent.start_link(fn -> initial_state end)
end
```

#### 3. Start the Agent at Runtime

In your running application (e.g., from a controller, another GenServer, or a remote `iex` shell), call `DynamicSupervisor.start_child/2`. This immediately spawns the agent and adds it to the supervision tree.

```elixir
# Start a new agent with "initial_data" as its state
{:ok, agent_pid} = DynamicSupervisor.start_child(
  MyApp.AgentSupervisor,
  {MyApp.MyAgent, "initial_data"}
)
```

### Managing Running Agents

- **No Restarts Required:** Once `MyApp.AgentSupervisor` is part of your running application, you can call `start_child/2` as many times as needed to spin up new agents without ever restarting the app or the supervisor.

- **Auto-Cleanup:** If an agent finishes its task or crashes, the supervisor will handle it according to the restart strategy defined in the agent's `child_spec` (e.g., `:temporary`, `:transient`, or `:permanent`).

- **Locating Agents:** Since `start_child` returns a PID, you may want to use an Elixir `Registry` to name and find these agents later by a unique ID instead of keeping track of PIDs manually.

---

## Part 7: Spawning a tmux Session per Agent with Claude Code

To spawn a `tmux` session for a running Elixir Agent and execute Claude Code within it, you use Elixir's `System.cmd/3` to interface with the host's terminal.

### 1. Updated Agent Logic

Modify your Agent's `init` or `start_link` to trigger the `tmux` command. It is best to use a unique name for each session (like an MD5 hash of the project path or a UUID) so you can track them easily.

```elixir
defmodule MyApp.ClaudeAgent do
  use Agent

  def start_link(project_path) do
    # 1. Create a unique session name
    session_id = "claude_#{:erlang.phash2(project_path)}"

    # 2. Start the tmux session in the background
    #    and run the 'claude' command immediately
    System.cmd("tmux", [
      "new-session", "-d",
      "-s", session_id,
      "-c", project_path,
      "claude"
    ])

    Agent.start_link(fn -> %{session_id: session_id, path: project_path} end)
  end
end
```

### 2. Implementation Steps

1. **Session Creation:** The `-d` flag in the `tmux new-session` command is critical; it starts the session detached so your Elixir process doesn't hang waiting for the terminal to close.

2. **Claude Code Initiation:** By passing `"claude"` as the final argument to the `tmux` command, the agent immediately begins its interactive session inside that specific terminal environment.

3. **Persistence:** Because `tmux` is a multiplexer, the Claude Code process will continue running even if the Elixir Agent crashes or if you detach from the session.

### 3. Accessing the Agent

Once the agent is started via your `DynamicSupervisor`, you can "jump into" its terminal from your own command line:

```bash
# To see all running Claude agents:
tmux list-sessions

# To attach to a specific agent's session:
tmux attach-session -t <session_id>
```

### Best Practices

- **Teammate Mode:** If you want Claude to automatically handle multiple panes within that session, you can use the `--teammate-mode tmux` flag when starting the command.

- **Cleanup:** Consider adding a `terminate/2` callback to your Agent that runs `System.cmd("tmux", ["kill-session", "-t", session_id])` if you want the terminal to close when the Elixir process stops.

---

## Part 8: Auto-Detecting Existing tmux Sessions

To auto-detect and re-sync with existing `tmux` sessions after an application crash or restart, you can use the `tmux has-session -t session_id` command. This allows your Agent to check for an existing environment before attempting to create a new one.

### 1. Updated Agent with Detection Logic

Modify your Agent to perform a check during initialization. If the session exists, it attaches; if not, it creates a new one.

```elixir
defmodule MyApp.ClaudeAgent do
  use Agent

  def start_link(project_path) do
    session_id = "claude_#{:erlang.phash2(project_path)}"

    # Check if session already exists
    {_output, exit_code} = System.cmd("tmux", ["has-session", "-t", session_id])

    if exit_code != 0 do
      # Start new session if it doesn't exist
      System.cmd("tmux", ["new-session", "-d", "-s", session_id, "-c", project_path, "claude"])
    else
      # Session exists; optionally send a command to it
      System.cmd("tmux", ["send-keys", "-t", session_id, "echo 'Agent reconnected'", "Enter"])
    end

    Agent.start_link(fn -> %{session_id: session_id, path: project_path} end)
  end
end
```

### 2. Auto-Restoring Multiple Agents

If your whole application crashes, you need a way to "remember" which Agents were running so the `DynamicSupervisor` can restart them.

- **Persistence Layer:** Store a list of active `project_paths` in a database (like Ecto) or a simple file.

- **Recovery Task:** Create a simple `Task` or `GenServer` in your supervision tree that runs once at startup. This task reads the stored paths and calls `DynamicSupervisor.start_child/2` for each one.

- **Handshake:** Because of the `has-session` check above, each restarted Agent will automatically find its existing `tmux` session and resume control of Claude Code without creating duplicates.

### 3. Monitoring Health

You can add a periodic check using `Process.send_after/3` inside a GenServer version of your agent to verify the `tmux` session is still alive. If `tmux has-session` returns a non-zero exit code, the Agent can automatically recreate the session.

---

## Part 9: Register the Agent by ID (GenServer version)

Switching to `GenServer` to support registration, health monitoring, and inter-agent communication.

### Register the Agent by ID

Modify your Agent to register itself using a unique ID (e.g., `"project_a"`). This allows you to find the Agent without knowing its PID.

```elixir
defmodule MyApp.ClaudeAgent do
  use GenServer # Switching to GenServer for registration + health monitoring

  def start_link(id, project_path) do
    # Register under a unique name in the Registry
    GenServer.start_link(__MODULE__, {id, project_path},
      name: {:via, Registry, {MyApp.AgentRegistry, id}})
  end

  def init({id, path}) do
    session_id = "claude_#{id}"
    # Start tmux session if it doesn't exist
    System.cmd("tmux", ["new-session", "-d", "-s", session_id, "-c", path, "claude"])
    {:ok, %{id: id, session_id: session_id, path: path}}
  end
end
```

---

## Part 10: Communicate Between Agents

To send a message from **Agent A** to **Agent B**'s Claude Code session, you use the Registry to find the target and `tmux send-keys` to "type" into their terminal.

### Send a command to a specific Agent:

```elixir
defmodule MyApp.Commander do
  def send_to_agent(target_id, message) do
    # Look up the session_id from the Registry
    [{_pid, %{session_id: sess}}] = Registry.lookup(MyApp.AgentRegistry, target_id)

    # Send the string + 'Enter' key to the target's tmux pane
    System.cmd("tmux", ["send-keys", "-t", sess, message, "Enter"])
  end
end

# Usage:
MyApp.Commander.send_to_agent("project_a", "/help")
```

---

## Part 11: Direct Agent-to-Agent Talk

If **Agent A** needs to trigger an action in **Agent B** automatically:

1. **Agent A** calls `Registry.lookup/2` for `"project_b"`.
2. **Agent A** uses `System.cmd` to push a command into **Agent B**'s `tmux` pane.
3. **Claude Code** in session B receives the text as if a human typed it.

### Pro Tip: Capturing Output

If you want **Agent A** to "read" what is happening in **Agent B**'s session, use:

```elixir
System.cmd("tmux", ["capture-pane", "-p", "-t", session_id])
```

This returns the current visible text of the terminal as an Elixir string. You can use this to scrape the last 10 lines of a session to pass context between Claudes.
