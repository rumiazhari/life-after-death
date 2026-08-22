# Voxel gameplay contract

This milestone ports the player-facing combat slice into the isolated
`VoxelIsometricPrototype.tscn`. It does not replace the production 2D player,
weapons, projectiles, interactions, or `Main.tscn`.

## Shared contracts

The 3D player and zombie use the existing `HealthComponent`. Player health,
damage, death, respawn, weapon ammunition, reload, equipped-slot, and
interaction-prompt events continue through the existing `GameEvents` autoload.
Three explicitly 3D signals were added because the existing zombie and
explosion signals require `Node2D` and `Vector2`: `voxel_zombie_damaged`,
`voxel_zombie_died`, and `voxel_environment_explosion`.

The player continues to read movement, aim, fire, reload, interaction, and
weapon-slot requests exclusively from `InputRouter`. `VoxelAimProjector`
converts its screen-space aim vector into a `Camera3D` ray and intersects that
ray with the player's horizontal plane. Gameplay code does not read mouse or
touch devices directly.

## Weapons and projectiles

`VoxelWeapon3D` consumes the existing `smg.tres` and
`breaching_charge.tres` `WeaponData` resources. Damage, fire rate, magazine,
reserve ammunition, reload duration, spread, automatic/semi-automatic mode,
and structural damage class are unchanged. The resources' pixel-space
projectile speed and blast radius are divided by 32, matching
`VoxelCoordinates.SEMANTIC_PIXELS_PER_VOXEL`.

The two weapon nodes retain their own magazine, reserve, cooldown, and reload
state when the player changes slots. `VoxelPrototypeProjectileManager`
prewarms 32 `Area3D` projectiles and reuses them. Projectiles perform a 3D ray
query over each physics-step movement segment, preventing high-speed rounds
from passing through thin geometry.

## Interaction

`VoxelInteractor3D` mirrors the existing `PlayerInteractor` selection rule. It
tracks only overlapping collision-layer-64 `Area3D` candidates, ignores
disabled `InteractableComponent`s, and applies the same facing preference
before invoking exactly one interaction per request. The existing generic
`InteractableComponent` is reused under the 3D door and loot areas.

## Structural damage

`VoxelStructuralDamageService` resolves a hit to a stable world `Vector3i`
cell. Material definitions supply durability and the minimum accepted damage
class. Brick requires explosive damage, roof material requires heavy damage,
and glass or wood accepts small arms.

Accepted damage writes a sparse override into `VoxelWorldData`. At zero
durability the cell is removed from `VoxelChunkData`, and every registered
material renderer for that chunk rebuilds its merged mesh and trimesh
collision. Explosion damage enumerates cells within the converted 3D radius
and applies the same persisted cell contract with linear falloff bounded to
25 percent.

## Verification

`tests/voxel/voxel_prototype_smoke.gd` covers camera-ray projection, health,
actor projectile damage, weapon switching, independent ammunition, reload,
projectile pooling, door and loot interactions, roof visibility, structural
damage rejection and destruction, collision rebuild, blast-radius conversion,
explosion events, and persistent voxel overrides.
