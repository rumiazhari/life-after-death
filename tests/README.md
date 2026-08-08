# tests

`test_runner.gd` + `TestRunner.tscn` are a lightweight headless
regression suite (no external test framework) covering the survivor
inventory/job data-integrity lifecycle added in Phase 2A.1: reservation
success/failure, capacity-aware scavenging, haul-job interruption before
and after pickup, survivor death retaining a persistent `SurvivorData`
record, and restart resetting `WorldState`/`SimulationClock`. Every test
asserts exact item conservation (nothing duplicated or destroyed) except
where an item was deliberately consumed.

Run from the project root:

```
godot --headless --path . res://tests/TestRunner.tscn
```

Exits 0 if every test passes, nonzero otherwise -- safe to use as a
pre-commit/CI gate. Tests construct data types (`Inventory`, `Job`,
`SettlementJobBoard`, `StorageContainer`, `ScavengePoint`) directly rather
than spinning up a full `Main.tscn` play session, and reset
`WorldState`/`SimulationClock` before each test so they can't leak state
into each other.

The rest of the vertical slice (combat, input, movement, the utility-AI
decision loop end to end) was validated manually through the godot-ai MCP
connection: live scene inspection, simulated input, and log monitoring
across extended play sessions. See the project README and
`docs/architecture.md` for what was exercised.
