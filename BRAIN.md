# BRAIN -- Session Knowledge

## Inline Pattern (Control Wrappers)

When inlining a module that is itself used by another module being inlined (e.g., Lookup used by RuntimeQuery), handle the dependency chain in the right order:
1. Inline the leaf (Lookup) first into its non-deleted callers
2. When inlining the intermediate (RuntimeQuery), re-inline the leaf's logic directly into the intermediate's private helpers

## format hook / alias sorting side-effect

The mix format hook re-sorts aliases alphabetically when it fires after an Edit. If the existing codebase uses `Ichor.Events.Runtime, as: EventRuntime` but you write `alias Ichor.EventBuffer`, the hook may restore the original alias and update callsites. Trust the file state after hook fires -- check grep before overriding.

## Private defp naming in DashboardDagHandlers

`find_agent_entry` calls `find_session_name` which calls `fallback_session_name` which calls `find_agent_by_id`. Named `find_agent_by_id` (not `find_agent`) to avoid collision with existing names.

## RuntimeQuery.fallback_session_name agent field access

Original code used both `agent[:name]` (bracket) and `agent["name"]` (string bracket) to cover both atom and string key maps. This was already in the source -- preserved as-is.
