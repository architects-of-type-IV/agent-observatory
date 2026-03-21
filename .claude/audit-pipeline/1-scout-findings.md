# Stage 1: Scout Findings -- Full Code Review

3 parallel scouts: backend, frontend, infrastructure. Deduplicated.

## CRITICAL (7)

| ID | File | Issue |
|----|------|-------|
| C1 | `factory/jsonl_store.ex:17` | jq injection -- agent-controlled input in jq program string |
| C2 | `infrastructure/tmux/script.ex:50` | Shell injection -- agent name in shell script unsanitized |
| C3 | `ichor_web/live/dashboard_messaging_handlers.ex:56` | Path traversal -- client file_path read without validation |
| C4 | `signals/bus.ex:31` | Bare match crashes caller on tmux delivery failure |
| C5 | `signals/agent_watchdog.ex:256` | Bare match kills watchdog if HITLRelay down |
| C6 | `signals/runtime.ex:24` | `true = info.dynamic` MatchError on non-dynamic signals |
| C7 | `ichor_web/controllers/event_controller.ex:28` | Bare match crashes controller on ingest failure |

## HIGH (13)

| ID | File | Issue |
|----|------|-------|
| H1 | `ichor_web/controllers/export_controller.ex:93` | CSV/formula injection -- no field escaping |
| H2 | `ichor_web/live/dashboard_live.ex:143` | stream_insert before stream configured crashes LV |
| H3 | `factory/runner.ex:238` | handle_cast returns command fn result directly |
| H4 | `factory/board.ex:70` | String.to_integer crashes on non-numeric filenames |
| H5 | `workshop/spawn.ex:27` | Bang call violates {:ok, _} | {:error, _} spec |
| H6 | `infrastructure/agent_process.ex:304` | Unbounded unread list for active agents |
| H7 | `application.ex:14` | Blocking tmux spawn in start/2 |
| H8 | `ichor_web/live/dashboard_mes_handlers.ex:69` | File.cwd! + File.write! crash risk |
| H9 | `ichor_web/live/dashboard_messaging_handlers.ex:38` | Missing error clause in team broadcast |
| H10 | `ichor_web/live/dashboard_session_control_handlers.ex:37` | PubSub subscription leak |
| H11 | `ichor_web/live/dashboard_state.ex:123` | Silent ArgumentError swallow hides bugs |
| H12 | `factory/lifecycle_supervisor.ex:23` | Side effects on failed supervisor start |
| H13 | `signals/event_stream.ex:53` | Tombstoned session signals emitted |
