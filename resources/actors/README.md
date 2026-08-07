# resources/actors

Reserved for future data-driven actor tuning (e.g. per-zombie-type or
per-survivor-type stat resources), mirroring the `WeaponData` pattern in
`resources/weapons/`. Player and zombie tuning currently lives as
`@export` fields directly on `player.gd` / `zombie.gd` since there is
only one variant of each in this slice.
