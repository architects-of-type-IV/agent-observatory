# Codex Findings

1. **BUG**: EventBufferReader defaults to `Ichor.EventBuffer` which doesn't exist
2. **BUG**: event.ex `:recent` action shape mismatch with Buffer.recent/1
3. **Doc drift**: Catalog docs say strict, implementation is permissive (lookup_or_derive)
4. **Brittle**: load_task_projections.ex fabricates IDs, String.to_existing_atom crash risk
5. **Overscoped docs**: ProtocolTracker claims more than it does
6. **Dead code**: TraceEvent struct unused
7. **Dead code**: publish_fact/2 no callers, wrong emit shape
8. **Design note**: Monotonic timestamps (fine for single-node)
