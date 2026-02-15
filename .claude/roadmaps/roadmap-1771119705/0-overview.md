# Agent Messaging Investigation

## Problem
Observatory's agent messaging pipeline (Dashboard <-> Agent via MCP) doesn't work reliably.
User has tried many times. MCP tools were verified individually but end-to-end flow fails.

## 3-Phase Structure

### Phase 1: Discovery (Team: messaging-discovery)
Deep investigation of what exists, what's broken, and how MCP agent messaging should work.
- **researcher**: External research on MCP protocol, Claude Code agent messaging, tool_use patterns
- **tracer**: Codebase trace of full message flow (Dashboard -> Mailbox -> CommandQueue -> Agent -> MCP -> back)
- **tester**: Reproduce failures - actually send messages and document what breaks

### Phase 2: Analysis (Team: messaging-analysis)
Compare findings, identify root causes, analyze options.
- **protocol-analyst**: Compare Observatory implementation vs MCP spec and best practices
- **architecture-analyst**: Identify structural issues (ETS vs filesystem, dual-write, PubSub gaps)
- **integration-analyst**: Identify wiring gaps (LiveView -> handler -> Mailbox -> CommandQueue -> Agent)

### Phase 3: Solution (Team: messaging-fix)
Design and implement fixes based on Phase 2 diagnosis.
- **backend-dev**: Fix Mailbox, CommandQueue, MCP tool definitions
- **frontend-dev**: Fix LiveView handlers, PubSub subscriptions, UI components
- **verifier**: End-to-end testing, edge cases, documentation

## Key Questions
1. Does the MCP server actually receive messages from agents?
2. Does the CommandQueue filesystem inbox get read by Claude Code agents?
3. Does PubSub correctly notify the LiveView when agent messages arrive?
4. Is the message format correct (AshAi input nesting)?
5. Are there timing/race conditions?
