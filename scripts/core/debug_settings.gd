extends Node
## Central debug/testing switches. Autoloaded as `DebugSettings`.
## Flip a flag here (or at runtime) to toggle behavior project-wide.

## TEMPORARY: the player never exhausts reserve ammunition while this is on.
## Magazines still cycle through normal reload mechanics; NPC weapons are not
## affected. Set to false to restore fully normal consumption.
var infinite_player_ammo := true