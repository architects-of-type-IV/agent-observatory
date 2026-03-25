# ICHOR IV Architecture Diagrams

Related: [Vertical Slices](../plans/2026-03-21-vertical-slices.md) | [Architecture Audit](../plans/2026-03-21-architecture-audit.md) | [Glossary](../plans/GLOSSARY.md) | [Database Schema](database-schema.md)

---

## Concepts: What Signals Actually Is

Signals is the nervous system. Everything that happens in the app becomes a signal. Anything that needs to react subscribes. No direct cross-domain calls needed.

```mermaid
graph LR
    subgraph "Things That Happen"
        A[agent starts working]
        B[agent goes silent]
        C[run completes]
        D[task gets claimed]
        E[operator sends message]
    end

    subgraph "Signals"
        S((PubSub))
    end

    subgraph "Things That React"
        F[dashboard updates]
        G[watchdog checks health]
        H[cleanup archives run]
        I[board refreshes]
        J["~~mesh builds topology~~\n(Mesh deleted f20ac4b)"]
    end

    A --> S
    B --> S
    C --> S
    D --> S
    E --> S

    S -.-> F
    S -.-> G
    S -.-> H
    S -.-> I

    style S fill:#fff3e0,stroke:#e65100,stroke-width:3px
```

**The rule:** producers emit, subscribers react. A producer never knows who's listening. A subscriber never calls the producer. Signals is the only coupling point between domains.

---

## Concepts: What Spawn Actually Is

`spawn/1` is generic. Give it a team name, it compiles the Workshop design and launches agents in tmux. What the team does is defined by its prompts -- configured in Workshop, not hardcoded.

```mermaid
graph TB
    subgraph "Any trigger"
        A["Button: Resume"]
        B["Button: Mode A"]
        C["Button: Build"]
        D["Button: Launch Team"]
        E["Timer: MesScheduler tick"]
        F["Future: API call"]
    end

    subgraph "One function"
        G["spawn(team_name)"]
    end

    subgraph "Workshop"
        H["Look up team design"]
        I["Load agents, prompts, spawn links"]
        J["Compile to TeamSpec"]
    end

    subgraph "Infrastructure"
        K["TeamLaunch.launch"]
        L["Write scripts"]
        M["Create tmux session"]
        N["Register in fleet"]
    end

    O["Team running in tmux"]

    A --> G
    B --> G
    C --> G
    D --> G
    E --> G
    F --> G

    G --> H
    H --> I
    I --> J
    J --> K
    K --> L
    L --> M
    M --> N
    N --> O

    style G fill:#e8f5e8,stroke:#2e7d32,stroke-width:3px
    style O fill:#e8f5e8
```

**The rule:** spawn doesn't know what the team will do. It just compiles and launches. Team behavior comes from Workshop-configured prompts.

---

## Concepts: How Constraints Work (no new abstractions)

Constraints on spawning are just pattern matches in signal subscribers. No "Policy" module needed.

```mermaid
sequenceDiagram
    participant Any as Any Trigger
    participant S as spawn/1
    participant Sig as Signals
    participant Sub as Subscriber (handle_info)
    participant Fleet as Fleet Registry

    Any->>S: spawn("mes")
    S->>Sig: emit :team_spawn_requested, %{team: "mes"}

    Note over Sub: handle_info matches team: "mes"
    Sig-->>Sub: :team_spawn_requested

    Sub->>Fleet: any "mes" team running?
    Fleet-->>Sub: yes / no

    alt Already running
        Sub->>Sub: ignore (no action)
    else Not running
        Sub->>S: proceed with compile + launch
        S->>S: compile Workshop design
        S->>S: TeamLaunch.launch
        S->>Sig: emit :team_spawned, %{team: "mes"}
    end

    Note over Sub: Different team names = different clauses.<br/>No "mes" clause? Spawn freely.
```

---

## Concepts: Workshop Owns Design, Not Execution

Workshop is where teams are designed. Spawn is where they come alive. The prompt builder in Workshop defines what agents do -- the rest is infrastructure.

```mermaid
graph TB
    subgraph "Workshop (design time)"
        A[Canvas: arrange agents]
        B[Configure roles + models]
        C[Set spawn links: who starts after whom]
        D[Set comm rules: who talks to whom]
        E["Write prompts per agent slot"]
        F[Save as Team]
    end

    subgraph "Spawn (launch time)"
        G["spawn(team_name)"]
        H[Load Team from DB or Preset]
        I[Compile: CanvasState + Prompts -> TeamSpec]
        J[Launch: scripts + tmux + register]
    end

    subgraph "Running (runtime)"
        K[Agents follow their prompts]
        L[Agents communicate via Bus]
        M[Signals broadcast what happens]
        N[Subscribers react]
    end

    A --> B --> C --> D --> E --> F
    F -->|"team name"| G
    G --> H --> I --> J
    J --> K --> L --> M --> N

    style F fill:#e8f5e8,stroke:#2e7d32
    style G fill:#e8f5e8,stroke:#2e7d32
    style M fill:#fff3e0,stroke:#e65100
```

---

## Concepts: The MES Page as Factory Floor

The `/mes` page is a control panel. Every button either spawns a team or produces artifacts for a future spawn.

```mermaid
graph TB
    subgraph "MES Page Controls"
        R["Resume / Pause"]
        MA["Mode A (discover)"]
        MB["Mode B (define)"]
        MC["Mode C (build)"]
        GC["Gate Check"]
        GD["Generate DAG"]
        BD["Build"]
    end

    subgraph "What They Do"
        R -->|"spawn('mes')"| T1["MES research team runs"]
        MA -->|"spawn('planning-a')"| T2["Mode A team produces ADRs"]
        MB -->|"spawn('planning-b')"| T3["Mode B team produces FRDs"]
        MC -->|"spawn('planning-c')"| T4["Mode C team produces roadmap"]
        GC -->|"no spawn"| V["Validate gate readiness"]
        GD -->|"no spawn"| W["Generate tasks.jsonl from roadmap"]
        BD -->|"spawn('pipeline')"| T5["Build team executes tasks"]
    end

    subgraph "All Teams Come From Workshop"
        WS["Workshop team configs"]
        WS -.->|"'mes' config"| T1
        WS -.->|"'planning-a' config"| T2
        WS -.->|"'planning-b' config"| T3
        WS -.->|"'planning-c' config"| T4
        WS -.->|"'pipeline' config"| T5
    end

    style WS fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
    style R fill:#fff3e0
    style BD fill:#e3f2fd
```

---

## Domain Boundaries

> **Note (2026-03-25)**: Fleet domain was not implemented as a separate Ash domain. Fleet functionality remains in Infrastructure (FleetSupervisor, AgentProcess). The Mesh domain was deleted in f20ac4b. AshSqlite was replaced by AshPostgres.

```mermaid
graph TB
    subgraph Workshop["Workshop Domain (design)"]
        direction TB
        Team[Team]
        TM[TeamMember]
        AT[AgentType]
        Agent[Agent]
        ActiveTeam[ActiveTeam]
        AM[AgentMemory]
        Presets[Presets]
        TS[TeamSpec compiler]
    end

    subgraph Factory["Factory Domain (execution)"]
        direction TB
        Project[Project]
        Pipeline[Pipeline]
        PT[PipelineTask]
        Floor[Floor]
        Runner[Runner GenServer]
        Spawn[Spawn orchestrator]
        Loader[Loader]
        PDW[ProjectDiscoveryWorker\nOban cron]
    end

    subgraph Archon["Archon Domain (system agent)"]
        direction TB
        Manager[Manager]
        Memory[Memory]
    end

    subgraph SignalBus["SignalBus Domain (reactive backbone)"]
        direction TB
        Ops[Operations]
        ES[EventStream store]
        Bus[Bus delivery]
        Router[Router GenStage]
        SP[SignalProcess accumulators]
        AH[ActionHandler]
        Checkpoint[Checkpoint]
    end

    subgraph Events["Events Domain"]
        direction TB
        Ingress[Ingress GenStage]
        StoredEvent[StoredEvent]
    end

    subgraph Projectors["Projector namespace"]
        direction TB
        AW[AgentWatchdog]
        TW[TeamWatchdog]
        SM[SignalManager]
        SB[SignalBuffer]
        FL[FleetLifecycle]
        CD[CleanupDispatcher]
    end

    subgraph Infra["Infrastructure (host layer)"]
        direction TB
        FS[FleetSupervisor]
        AP[AgentProcess]
        TL[TeamLaunch]
        Tmux[Tmux adapter]
        HITL[HITLRelay]
        Reg[Registry]
    end

    Workshop -->|"compile spec"| Infra
    Factory -->|"launch teams"| Workshop
    Factory -->|"launch via"| Infra
    SignalBus -.->|"signals"| Workshop
    SignalBus -.->|"signals"| Factory
    SignalBus -.->|"signals"| Archon
    SignalBus -.->|"signals"| Infra
    SignalBus -->|"feeds"| Events
    Events --> SignalBus
    Archon -->|"MCP actions"| Workshop
    Archon -->|"MCP actions"| Factory
    Projectors -.->|"subscribe to signals"| SignalBus

    style Workshop fill:#e8f5e8,stroke:#2e7d32
    style Factory fill:#e3f2fd,stroke:#1565c0
    style Archon fill:#f3e5f5,stroke:#7b1fa2
    style SignalBus fill:#fff3e0,stroke:#e65100
    style Events fill:#fff8e1,stroke:#f57f17
    style Projectors fill:#fce4ec,stroke:#880e4f
    style Infra fill:#eceff1,stroke:#546e7a
```

---

## UC2: Launch a Team (Workshop)

### Sequence: User launches a saved team

```mermaid
sequenceDiagram
    participant UI as Dashboard
    participant WH as WorkshopHandlers
    participant Ash as Team.spawn_team
    participant WS as Workshop.Spawn
    participant TSH as TeamSpawnHandler
    participant TS as TeamSpec
    participant TL as TeamLaunch
    participant Tmux as tmux

    UI->>WH: ws_launch_team
    WH->>Ash: Team.spawn_team(name)
    Ash->>WS: spawn_team(name)
    WS->>WS: build_spec(team, members)
    WS->>TSH: emit :team_spawn_requested
    Note over WS: awaits signal (30s timeout)
    TSH->>TL: TeamLaunch.launch(spec)
    TL->>TL: Scripts.write_all(spec)
    TL->>Tmux: Session.create_all
    Tmux-->>TL: windows created
    TL->>TL: Registration.register_all
    TSH-->>WS: emit :team_spawn_ready
    WS-->>Ash: {:ok, result}
    Ash-->>UI: flash success
```

### Flow: Spec compilation

```mermaid
flowchart LR
    A[Team from DB] --> B[CanvasState.apply_team]
    C[or Preset] --> B
    B --> D[canvas_state]
    D --> E[build_from_state]
    F[prompt_builder fn] --> E
    G[agent_metadata fn] --> E
    E --> H[iterate agents in spawn_order]
    H --> I[AgentSpec.new per agent]
    I --> J[Infrastructure.TeamSpec]

    style A fill:#e8f5e8
    style C fill:#e8f5e8
    style J fill:#eceff1
```

---

## UC3+UC4: Planning and Pipeline Launch (Factory)

### Sequence: User starts a pipeline build

```mermaid
sequenceDiagram
    participant UI as MES Page
    participant MH as MesHandlers
    participant FS as Factory.Spawn
    participant L as Loader
    participant V as Validator
    participant WG as WorkerGroups
    participant TS as TeamSpec
    participant TL as TeamLaunch
    participant R as Runner
    participant Tmux as tmux

    UI->>MH: mes_launch_dag
    MH->>FS: spawn(:pipeline, project_id)
    FS->>L: from_project(project_id)
    L-->>FS: Pipeline + PipelineTasks
    FS->>V: validate_pipeline(tasks)
    V-->>FS: :ok
    FS->>WG: build(tasks)
    WG-->>FS: worker_groups
    FS->>TS: build(:pipeline, run, session, brief, tasks, groups, ctx)
    TS-->>FS: Infrastructure.TeamSpec
    FS->>TL: TeamLaunch.launch(spec)
    TL->>Tmux: create session + windows
    Tmux-->>TL: running
    FS->>R: Runner.start(:pipeline, opts)
    R->>R: subscribe to signals
    R->>R: schedule checks
```

### Flow: Three spawn paths converge

```mermaid
flowchart TB
    subgraph "Triggers"
        A[MES Scheduler tick]
        B["User: Build (pipeline)"]
        C["User: Mode A/B/C (planning)"]
        D["User: Launch Team (workshop)"]
    end

    subgraph "Context Providers"
        A --> E[Runner.start :mes]
        E --> F[mes_on_init hook]
        F --> G["TeamSpec.build(:mes)"]

        B --> H["Factory.Spawn(:pipeline)"]
        H --> I[Loader + Validator + WorkerGroups]
        I --> J["TeamSpec.build(:pipeline)"]

        C --> K["Factory.Spawn(:planning)"]
        K --> L["TeamSpec.build(:planning)"]

        D --> M[Workshop.Spawn]
        M --> N["Infrastructure.TeamSpec.new (direct)"]
    end

    subgraph "Convergence"
        G --> O[Infrastructure.TeamLaunch.launch]
        J --> O
        L --> O
        N --> O
    end

    subgraph "Infrastructure"
        O --> P[Scripts.write_all]
        P --> Q[Session.create_all]
        Q --> R[Registration.register_all]
        R --> S[Agents running in tmux]
    end

    style O fill:#fff3e0,stroke:#e65100,stroke-width:3px
    style S fill:#e8f5e8
```

---

## UC5: Monitor the Fleet

### Sequence: Hook event to dashboard update

```mermaid
sequenceDiagram
    participant Claude as Claude Agent
    participant Hook as Hook Script
    participant EC as EventController
    participant ES as EventStream
    participant ETS as ETS Buffer
    participant Sig as Signals PubSub
    participant ING as Events.Ingress
    participant Router as Signals.Router
    participant SP as SignalProcess
    participant AW as AgentWatchdog
    participant LV as Dashboard LiveView
    participant UI as Browser

    Claude->>Hook: tool use triggers hook
    Hook->>EC: POST /api/events
    EC->>ES: ingest_raw(event_attrs)
    ES->>ES: Normalizer.build_event
    ES->>ETS: insert event
    ES->>Sig: emit :new_event
    ES->>ES: AgentLifecycle.resolve_or_create_agent

    par Signal Subscribers
        Sig-->>AW: :new_event
        AW->>AW: update session activity
        AW->>AW: clear escalation if active
    and
        Sig-->>LV: :new_event
        LV->>LV: recompute assigns
        LV->>UI: push diff
    and
        Note over ING: also feeds GenStage pipeline
        Sig-->>ING: push event
        ING->>Router: demand-driven
        Router->>SP: route to signal modules
    end
```

### Flow: AgentWatchdog beat cycle

```mermaid
flowchart TD
    A[":beat every 5s"] --> B[emit :heartbeat]
    B --> C[detect_and_handle_crashes]
    C --> D{any session stale > 120s?}
    D -->|No| F[run_escalation_check]
    D -->|Yes| E[check liveness]
    E --> E1{AgentProcess alive?}
    E1 -->|Yes| F
    E1 -->|No| E2{tmux window alive?}
    E2 -->|Yes| F
    E2 -->|No| E3[handle_crash]
    E3 --> E4[reassign tasks on Board]
    E4 --> E5[emit :agent_crashed]
    E5 --> E6[write inbox notification]
    E6 --> F

    F --> G[find stale agents]
    G --> H{escalation level?}
    H -->|0| I[emit :nudge_warning]
    H -->|1| J[Bus.send nudge message]
    H -->|2| K[HITLRelay.pause]
    H -->|3| L[emit :nudge_zombie]

    I --> M[scan_all_panes]
    J --> M
    K --> M
    L --> M

    M --> N[capture tmux output]
    N --> O{ICHOR_DONE?}
    O -->|Yes| P[emit :task_done]
    O -->|No| Q{ICHOR_BLOCKED?}
    Q -->|Yes| R[emit :task_blocked]
    Q -->|No| S[schedule next beat]

    P --> S
    R --> S

    style A fill:#fff3e0
    style E3 fill:#ffebee
    style S fill:#e8f5e8
```

---

## UC6: Agent Communication

### Sequence: Operator sends message to agent

```mermaid
sequenceDiagram
    participant UI as Dashboard
    participant MH as MessagingHandlers
    participant Bus as Signals.Bus
    participant Reg as Registry
    participant AP as AgentProcess
    participant Tmux as tmux
    participant ETS as Message Log
    participant Sig as Signals

    UI->>MH: send_agent_message
    MH->>Bus: Bus.send(%{to: agent_id, content: msg})
    Bus->>Bus: resolve(agent_id)
    Bus->>Reg: AgentProcess.alive?(agent_id)

    alt Agent process alive
        Bus->>AP: AgentProcess.send_message
        AP->>AP: route_message (deliver to backend)
    else Process dead, tmux alive
        Bus->>Tmux: Tmux.deliver(target, msg)
    else Neither alive
        Bus->>Bus: log warning, delivered=0
    end

    Bus->>ETS: log_delivery
    Bus->>Sig: emit :message_delivered
    Bus->>Sig: emit :fleet_changed
```

### Flow: Bus target resolution

```mermaid
flowchart LR
    A[target string] --> B{pattern?}
    B -->|"team:name"| C[TeamSupervisor.member_ids]
    C --> D[send to each member]
    B -->|"fleet:all"| E[AgentProcess.list_all]
    E --> D
    B -->|"role:worker"| F[filter by role metadata]
    F --> D
    B -->|bare id| G[single agent delivery]

    D --> H[AgentProcess.send_message]
    G --> H

    style A fill:#e3f2fd
```

---

## UC7: Pipeline Task Management

### Flow: Two data sources

```mermaid
flowchart TB
    subgraph "Internal (our runs)"
        A[Factory.Spawn creates run] --> B[Pipeline Ash resource]
        A --> C[PipelineTask Ash resources]
        C --> D[Agent claims via MCP action]
        D --> E[Ash update :claim]
        E --> F[FromAsh notifier]
        F --> G[emit :pipeline_task_claimed]
    end

    subgraph "External (other projects)"
        H[External project tasks.jsonl] --> I[PipelineMonitor polls every 3s]
        I --> J[Parse JSONL to maps]
        J --> K[Compute DAG + stats]
        K --> L[Hold in GenServer state]
    end

    subgraph "Sync (write-through)"
        E --> M[Runner.Exporter.sync_task_to_file]
        M --> N[jq update tasks.jsonl]
    end

    subgraph "Dashboard reads"
        L --> O[Pipeline board UI]
        C --> O
    end

    style B fill:#e3f2fd
    style H fill:#fff3e0
    style N fill:#fff3e0
```

---

## UC8: Run Lifecycle Cleanup

### Sequence: Run completes, cleanup cascades

```mermaid
sequenceDiagram
    participant R as Runner
    participant Sig as Signals
    participant TW as TeamWatchdog
    participant Fac as Factory
    participant Infra as Infrastructure
    participant Inbox as ~/.claude/inbox/

    R->>R: detect completion
    R->>Sig: emit :run_complete

    Note over TW: subscribes to :pipeline

    Sig-->>TW: :run_complete
    TW->>TW: cleanup_actions(run_id, kind)

    TW->>Fac: Pipeline.get + Pipeline.archive
    TW->>Fac: PipelineTask.by_run + reset each
    TW->>Infra: FleetSupervisor.disband_team
    TW->>Infra: Spawn.kill_session (tmux)
    TW->>Inbox: write JSON notification

    Note over TW: Problem: direct cross-domain calls
```

### Flow: Proposed signal-driven cleanup

```mermaid
flowchart TB
    A[Runner detects completion] --> B[emit :run_cleanup_needed]

    B --> C[Factory subscriber]
    B --> D[Infrastructure subscriber]
    B --> E[Operator.Inbox subscriber]

    C --> F[archive Pipeline]
    C --> G[reset PipelineTasks]

    D --> H[disband team]
    D --> I[kill tmux session]

    E --> J[write notification]

    F --> K[Oban job with retry]
    G --> K
    H --> L[Oban job with retry]
    I --> L
    J --> M[direct write]

    style B fill:#fff3e0,stroke:#e65100,stroke-width:3px
    style K fill:#e8f5e8
    style L fill:#e8f5e8
```

---

## Problem 1: TeamSpec Cross-Boundary

### Current: Caller knowledge inside compiler

```mermaid
flowchart LR
    subgraph Factory
        PP[PlanningPrompts]
    end

    subgraph Workshop
        TS[TeamSpec]
        TP[TeamPrompts]
        PiP[PipelinePrompts]
        Pre[Presets]
        CS[CanvasState]
    end

    subgraph Infrastructure
        IST[Infrastructure.TeamSpec struct]
    end

    PP -->|"imported into"| TS
    TP --> TS
    PiP --> TS
    Pre --> TS
    CS --> TS
    TS -->|produces| IST

    style PP fill:#ffebee,stroke:#c62828,stroke-width:2px
    style TS fill:#ffebee,stroke:#c62828,stroke-width:2px
```

### Proposed: Callers inject strategies

```mermaid
flowchart LR
    subgraph Factory
        PP[PlanningPrompts]
        FS["Spawn(:planning)"]
        FS2["Spawn(:pipeline)"]
        PiP[PipelinePrompts]
    end

    subgraph Workshop
        TS["TeamSpec.compile(state, opts)"]
        Pre[Presets]
        CS[CanvasState]
        TP[TeamPrompts]
        WS[Workshop.Spawn]
    end

    subgraph Infrastructure
        IST[Infrastructure.TeamSpec struct]
    end

    FS -->|"prompt_builder: &PP.mode_a/3"| TS
    FS2 -->|"prompt_builder: &PiP.worker/2"| TS
    WS -->|"prompt_builder: &TP.persona/2"| TS
    Pre --> TS
    CS --> TS
    TS -->|produces| IST

    style TS fill:#e8f5e8,stroke:#2e7d32,stroke-width:2px
```

---

## Signal Flow: The Reactive Backbone

> **Updated 2026-03-25**: GenStage pipeline added (ADR-026). PipelineMonitor replaced by ProjectDiscoveryWorker Oban cron.

```mermaid
flowchart TB
    subgraph Producers["Signal Producers"]
        EC[EventController]
        R[Runner]
        AP[AgentProcess]
        Ash[Ash Notifiers]
    end

    subgraph Bus["Signals PubSub"]
        SIG((Signals Bus))
    end

    subgraph GenStage["GenStage Pipeline ADR-026"]
        ING[Events.Ingress]
        RO[Signals.Router]
        SP[SignalProcess per key]
        AH[ActionHandler]
    end

    subgraph StoredEvents["Durable Storage"]
        SE[Events.StoredEvent]
        CP[Signals.Checkpoint]
    end

    subgraph Subscribers["Signal Subscribers"]
        AW[Projector.AgentWatchdog]
        TW[Projector.TeamWatchdog]
        LV[LiveView]
        PDW[ProjectDiscoveryWorker\nOban cron]
    end

    subgraph Reactors["Reactions"]
        OJ[Oban Jobs]
        UI[UI Update]
        ESC[Escalation / HITL]
    end

    EC -->|:new_event| SIG
    R -->|:run_complete| SIG
    AP -->|:fleet_changed| SIG
    Ash -->|:resource_changed| SIG

    SIG -.-> AW
    SIG -.-> TW
    SIG -.-> LV
    SIG --> ING

    ING --> SE
    ING --> RO
    RO --> SP
    SP --> AH
    AH --> ESC
    SP --> CP

    AW --> ESC
    TW --> OJ
    LV --> UI
    PDW --> OJ

    style SIG fill:#fff3e0,stroke:#e65100,stroke-width:3px
    style OJ fill:#e8f5e8
    style ING fill:#fff8e1,stroke:#f57f17
    style SE fill:#fff8e1,stroke:#f57f17
```

---

## Planned: Ichor.Discovery

```mermaid
flowchart TB
    subgraph Domains
        W[Workshop actions]
        F[Factory actions]
        A[Archon actions]
        S[SignalBus actions]
    end

    subgraph Discovery["Ichor.Discovery"]
        D[list_all_actions_by_domain]
        D --> CAT[Action Catalog]
    end

    subgraph "Workflow Builder UI"
        CAT --> WF[drag-and-drop pipeline]
        WF --> STEP1["Step 1: Factory.create_project"]
        STEP1 --> STEP2["Step 2: Factory.spawn(:planning)"]
        STEP2 --> STEP3["Step 3: wait_for signal"]
        STEP3 --> STEP4["Step 4: Factory.spawn(:pipeline)"]
    end

    W --> D
    F --> D
    A --> D
    S --> D

    style Discovery fill:#f3e5f5,stroke:#7b1fa2,stroke-width:2px
    style WF fill:#e3f2fd
```
