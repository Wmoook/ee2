# EE2 - Everybody Edits 2

A multiplayer 2D sandbox platformer inspired by Everybody Edits, built in Godot 4.

## How to Open

1. Open Godot 4.3+
2. Click "Import" and navigate to this folder
3. Select the `project.godot` file
4. Click "Import & Edit"
5. Godot will import all assets on first open (may take a moment)

## How to Play

### Host a Game
1. Launch the project (F5 in Godot editor)
2. Enter your name and choose a smiley (0-187)
3. Click **Host Game**
4. Share your IP address with friends

### Join a Game
1. Launch the project
2. Enter the host's IP address
3. Click **Join Game**

### Controls

| Key | Action |
|-----|--------|
| A/D or Left/Right | Move left/right |
| W/Up/Space | Jump |
| E | Toggle Edit Mode |
| G | Toggle God Mode (fly through walls) |
| LMB | Place block (in edit mode) |
| RMB | Erase block (in edit mode) |
| Scroll Wheel | Cycle block type |
| 1-9 | Quick select block |
| Ctrl+S | Save world (host only) |
| Escape | Return to menu |

## Features (MVP)

- **Exact EE Physics** - Ported from EEIO with authentic drag-based movement
- **Original EE Sprites** - All 700+ blocks from EE Offline, 188 smileys
- **Multiplayer** - ENet host/join, up to 8 players
- **Real-time Block Editing** - Place/remove blocks synced across all players
- **3 Layer System** - Foreground, background, decoration layers
- **Action Blocks** - Gravity arrows, dots, boost arrows, keys, doors/gates
- **Hazards** - Spikes, fire, lava with death animation
- **Dynamic Logic** - Moving platforms + color/state triggers
- **World Save/Load** - JSON-based world persistence
- **Late Join Sync** - New players receive the full world state
- **God Mode** - Fly through walls for building
- **Sample Room** - Pre-built test room with all features

## Block Types

- **Basic Bricks** - 13 colors (gray, red, orange, yellow, green, cyan, blue, purple, etc.)
- **Special Bricks** - Metal, glass, ice, marble, neon, castle, stone, and more
- **Extended Bricks** - 100+ additional brick styles
- **Action Blocks** - Gravity arrows (L/U/R/D), gravity dots, boost arrows
- **Hazards** - Spikes, fire, lava, colored spikes
- **Doors & Gates** - Red/green/blue doors and gates
- **Keys** - Red/green/blue keys (activate doors for 5 seconds)
- **Coins** - Yellow and blue coins
- **Decoration** - 100+ decorative blocks
- **Backgrounds** - 200+ background blocks

## Architecture

```
scripts/
  game_state.gd     - Block database, physics constants, global state (Autoload)
  network/
    network_manager.gd  - ENet multiplayer management (Autoload)
  world/
    world_manager.gd    - Authoritative world state (Autoload)
    world_renderer.gd   - Sprite-based tile rendering with atlas lookup
    block_editor.gd     - Mouse-based block placement/removal
    game_scene.gd       - Main game scene orchestrator
  player/
    ee_physics.gd       - Exact EE physics engine port
    player_controller.gd - Player scene with smiley, camera, networking
  logic/
    dynamic_objects.gd  - Moving platforms, triggers, state channels
  ui/
    main_menu.gd       - Host/join flow
    game_hud.gd        - In-game HUD
```

## TODO (v2)

- [ ] Minimap
- [ ] Chat system
- [ ] More action blocks (portals, team doors, NPC blocks)
- [ ] World browser / room list
- [ ] .eelvl file import
- [ ] Sound effects and music blocks
- [ ] Player animations (walking, jumping)
- [ ] Better camera with zoom controls
- [ ] Advanced logic: wiring, timers, counters
- [ ] Undo/redo for block editing
