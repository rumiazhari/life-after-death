# tests

`test_runner.gd` + `TestRunner.tscn` are a lightweight headless
regression suite (no external test framework) covering the survivor
inventory/job data-integrity lifecycle added in Phase 2A.1: reservation
success/failure, capacity-aware scavenging, haul-job interruption before
and after pickup, survivor death retaining a persistent `SurvivorData`
record, and restart resetting `WorldState`/`SimulationClock`. Every test
asserts exact item conservation (nothing duplicated or destroyed) except
where an item was deliberately consumed.

Phase 3B added coverage for the fixed urban district and its systems: the
district layout checksum, door/window open-closed movement+vision
blocking and exactly-once toggling, loot-container search and
salvage-once duplication prevention, persistent prop-container identity
and `WorldState.reset()` clearing Phase 3B state, building roof/room
reveal on enter/exit and through an open vs. closed door,
`ZombiePerceptionComponent`'s distance/cone/wall/hearing/search-timeout
gating, `UrbanNavigationService`'s door-cell solidity and per-frame
request budget, spawn-region point sampling, and a survivor's local
threat sensor ignoring a distant zombie behind a wall while still
reacting to a close one. See `docs/perception_system.md`,
`docs/building_system.md`, and `docs/interaction_system.md` for what
these systems do; the tests are the executable version of the same
contracts.

One test-harness note worth knowing if you add more tests here: several
pre-existing tests (`_make_survivor()` call sites) add a real `Survivor`
to the tree and never free it, since nothing in those tests' assertions
needed the `"attackable"` group to be clean afterward. Any new test that
scans that group globally (as `ZombiePerceptionComponent` does) should
place its fixtures at a clearly isolated world position (e.g. the
`(50000, 50000)` region the Phase 3B perception tests use) rather than
near the origin, where leaked survivors from earlier tests may still be
sitting.

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
