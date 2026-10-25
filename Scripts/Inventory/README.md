# Inventory & Crafting (The Forest style)

## Make a new item
1. Make a scene with your 3D object (RigidBody3D + mesh + CollisionShape3D works best).
2. Add an **InventoryItem** node as a direct child of the root. Fill in name, description, max carry.
3. Save the scene in `res://Scenes/Items/` (subfolders are fine).

Done: it can be picked up (E), shows on the inventory tarp as its own 3D model, and can be dropped (G).
If it looks too big/small or oddly turned on the tarp, tweak **Inventory Look** on the InventoryItem.

## Make it craftable
Add a **CraftingRecipe** node under the InventoryItem. In `ingredients`, add entries:
drag the ingredient item scenes in as keys, and set how many are needed.
More than one CraftingRecipe = more than one way to make it. `result_count` = how many one craft makes.

## Usable items (food, meds)
Fill **Using > use_effects** with player statistic names, e.g. `health: 10`.
Left click in the inventory applies it to the player's StatisticList (only stats that exist).
Listen to `Inventory.item_used(item_id)` for anything else (equipping, sounds...).

## Holding & inspecting
Left click an item in the inventory to hold it (click again to put it away). Food/meds are used instead.
In the world: F = inspect (mouse spins the item, F/Esc = back), X = put away, G = drop one.
Tweak how an item sits in the hand under **In Hand** on its InventoryItem (offset, rotation, scale).
Want a real arm? Open `Scenes/Inventory/hand_rig.tscn`, replace PlaceholderArm with your model and move `Grip` to where the item goes. Move `RestPoint` / `InspectPoint` to change the hold and inspect poses.

## Controls
I = inventory, E = take, RMB = to/from crafting mat (hold = batch), click cog or Space = craft,
LMB = use / hold, G = drop / clear mat, Esc = close.

## Code
`$PlayerInventory` (the Inventory node): `add_item(&"rock", 2)`, `remove_item()`, `count()`, `has_item()`,
`drop_item()`, signals `item_added`, `item_crafted`, `item_used`, `changed`, `opened`, `closed`.
