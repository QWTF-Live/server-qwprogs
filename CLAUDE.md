# CLAUDE.md — QWTF.live / FortressOne mod code

QuakeWorld Team Fortress reimplemented in QuakeC for the **FTE** engine. Three
separate progs are built from one tree:

| Output | Manifest | Runs in | Purpose |
|---|---|---|---|
| `qwprogs.dat` | `ssqc/progs.src` | server (SSQC) | authoritative game logic |
| `csprogs.dat` | `csqc/csprogs.src` | client (CSQC) | rendering, HUD, **prediction** |
| `menu.dat` | `menu/menu.src` | client menu VM | standalone FTE menusys |

The distinguishing feature of this codebase is that **CSQC re-simulates the
server's weapon, projectile, and player-movement state locally** so that firing,
reloading, grenade priming, animations and projectile flight have no round-trip
latency. Most of the difficulty in this tree lives in keeping those two
simulations agreeing.

## Build

```sh
make                      # builds all three .dat files with fteqcc64
LOGIN_SALT=<salt> make    # login token hashing needs the salt
./build.sh                # LOGIN_SALT=qwtfl!ve make && pkill fteqw-sv
./generate_ctags.sh       # regenerate ./tags via fteqcc -ftags
```

`fteqcc64` is vendored at the repo root (also fetched fresh by CI).
`version.sh` supplies `VER`/`REV` defines from git. `.dat`/`.lno` outputs are
gitignored. CI (`.github/workflows/workflow.yml`) builds `master` and `staging`
and uploads the `.dat`s to S3.

There is **no test suite**. The compiler is the only automated check — a clean
`make` ("Done. 0 warnings") is the bar. Verify behaviour in-game.

## Compiler notes (fteqcc, not vanilla QC)

This is heavily extended QuakeC. Expect and use:

- **C-like structs** with `->` and `.` access, arrays, `struct` initialiser
  tables (`weapon_info[]`, `fpp_types[]`, `fo_grenades[]`).
- **Pointers**: `float*`, `Type*`, `&expr`, `memalloc`/`memfree`
  (see `ssqc/rewind.qc` for a hand-rolled linked list).
- `enum` / `enumflags` (the latter auto-assigns 1,2,4,8…), `inline`, `static`,
  `const`, default args, `__out` params, varargs, `class` (`FOPlayer` in
  `ssqc/rewind.qc`).
- Token-pasting macros (`##`) are used for the whole network serialisation
  layer — one macro body compiles to both the send and the receive side.
- `#pragma target fte_5768`, `optimise 3`, `subscope`, `iffloat`.

Gotcha noted in `share/defs.h`: **`tfstate` bits past 24 are unsafe** with
bitops (QC float mantissa limits).

## Source layout

```
share/     compiled into BOTH ssqc and csqc — the prediction contract
ssqc/      server-only game logic
csqc/      client-only rendering, HUD, input, prediction driver
menusys/   FTE menu widget toolkit (upstream-ish)
menu/      the menu progs built on menusys
docs/      inherited TF 2.9 reference docs (tfentref, tfortmap, versions)
```

`SSQC` / `CSQC` are the guard macros. `share/fteextensions.qc` defines `SSQC`
when `QWSSQC` is set (server manifest does `#define QWSSQC`); `csqc/csdefs.qc`
defines `CSQC`. Shared files use `#ifdef SSQC` / `#else` to bind the same
algorithm to server entity fields on one side and the client's `pstate_pred`
struct on the other.

### `share/` — the shared simulation

| File | Contents |
|---|---|
| `defs.h` | all TF constants: `TFSTATE_*`, `PSTATE_*`, `PC_*` classes, `WEAP_*`, `STAT_*` (33–41), damage flags, `struct Slot` |
| `commondefs.qc` | `tf_config` (server→client tunables via `TMPL_CONFIG_DATA`), `MSG_*` CGAMEPACKET ids, `BUTTON_*`, `REWIND_*`, `TFX_*`, `CLOWN_*`, `CSQC_*` prediction-capability flags, `SERVER_FPS = 77` |
| `prediction.qc` | **core**: `predict_tf_state`, `FOWP_*` delta mask, send/recv of predict state, projectile entity protocol, `FO_CustomPhysics`, forward-projection math |
| `physics.qc` | `Phys_Advance` / `Phys_Init` / `Phys_Adv_Bounce` — the projectile integrator run identically on both sides |
| `weapons.qc` | `weapon_info[]`, `class_weapons[]`, `fo_grenades[]` tables; slot handling; reload state machine |
| `classes.qc` | shared LFSR PRNG (`shared_prng`, `PRNG_*` streams) and assault-cannon spread |
| `animate.qc` | weapon/player animation FSM, driven by `.client_think` and run under the time warp |
| `common_helpers.qc` | `ClientPred_Enabled()` — reads the client's advertised capabilities |
| `common_vote.qc`, `mcp_precache.qc`, `debug.qc` | vote data, precache lists, `ASSERT*`/`printf`/`PRINT_ONCE` macros |

### `ssqc/` — server

Entry points: `StartFrame` (`world.qc`), `PlayerPreThink` / `PlayerPostThink` /
`ClientConnect` / `ClientDisconnect` / `PutClientInServer` (`client.qc`),
`EndFrame` (`client.qc:3914`), `SV_ParseClientCommand` (`commands.qc`),
`CSEv_*_*` client→server events (`weapons.qc:2637`).

- `qw.qc` — the player entity field declarations (`.playerclass`, `.tfstate`,
  `.client_ping`, …). Start here when looking for "where does this field live".
- `time.qc` — `remote_time()` lag correction and the think warp (see below).
- `rewind.qc` — position history ring buffer + rollback (`FOPlayer` class).
- `tfort.qc`, `tfortmap.qc`, `tforttm.qc`, `tforthlp.qc` — TF core, map goal /
  `info_tfgoal` entity system, team management.
- Per-class files: `scout.qc`, `sniper.qc`, `tsoldier.qc`, `demoman.qc`,
  `medic.qc`, `hwguy.qc`, `pyro.qc`, `spy.qc`, `engineer.qc`, plus `sentry.qc`.
- `client.qc` (3.9k lines) — connection, spawning, per-frame player logic,
  `FO_GetUserSetting*` / `CF_GetSetting*` config accessors.
- Modes/meta: `clan.qc`, `quadmode.qc`, `vote.qc`, `spect.qc`, `coop.qc`,
  `admin.qc`, `login.qc`, `json.qc`, `events.qc` (JSON stats logging).
- `menu.qc` / `csmenu.qc` — server-driven in-game menus pushed to CSQC.

### `csqc/` — client

Entry points (`main.qc` unless noted): `CSQC_Init`, `CSQC_WorldLoaded`,
`CSQC_UpdateView`, `CSQC_ConsoleCommand`, `CSQC_Ent_Update`/`_Remove`,
`CSQC_Input_Frame`, `CSQC_Shutdown`; `CSQC_Parse_Event` (`events.qc`),
`CSQC_InputEvent` (`input.qc`).

- `weapon_predict.qc` (2.3k lines) — **the prediction driver**. Owns
  `pengine`, `pstate_pred`/`pstate_server` reconciliation, `WP_ClientThink`,
  `WP_Frame`, attack/reload/grenade prediction, predicted projectiles,
  view-model, ping tracking.
- `pmove.qc` — optional full client-side player movement prediction
  (`fo_pmove`), including nudges for explosion knockback, error smoothing.
- `tfx.qc` — outlines/shaders, team grenade timers, custom player skins.
- `hud.qc` / `status.qc` / `hud_helpers.qc` / `sui_sys.qc` — panel-based HUD
  (`PanelID` / `HUDP_*` in `csextradefs.qc`) plus its editor and UI toolkit.
- `settings.qc` — every client cvar, via `DEFCVAR_FLOAT/STRING`; read with
  `CVARF(name)` / `CVARS(name)` (thin wrappers over `autocvar_*`).
- `menu.qc`, `vote.qc`, `particles.qc`, `hitfeedback.qc`, `events.qc`,
  `profile.qc`.
- `csdefs.qc` is generated (`pr_dumpplatform`); don't hand-edit it.
  `csextradefs.qc` is the hand-written companion.

## The prediction system

### Capability negotiation

The client computes a bitmask of what it is predicting and publishes it as
userinfo:

```
csqc/weapon_predict.qc:WPP_UpdateEnable()
    → setlocaluserinfo(0, "fo_wpp_status", <CSQC_* bits>)
server: ClientPred_Enabled(client, CSQC_WEAP_PRED)   // share/common_helpers.qc
```

Bits (`share/commondefs.qc`): `CSQC_WEAP_PRED`, `CSQC_PROJ_PRED`, `CSQC_PMOVE`,
`CSQC_FORCE_POS`, `CSQC_SNIPER_SIGHT`. The server uses these to suppress
messages the client will generate itself (`sprint_pred()`), to enable pmove
handoff, and to skip server-side sniper dots.

Server tunables travel the other way as `tf_config`, declared once by the
`TMPL_CONFIG_DATA` X-macro and serialised by `TFL_SendConfig` /
`TFL_ReceiveConfig`. Server operators set them through `localinfo` (read by
`CF_GetSetting(short, long, default)`), players through `setinfo` (read by
`FO_GetUserSetting(ent, …)`).

### Predict state replication

`struct predict_tf_state` (`share/prediction.qc`) is the entire predicted
player state: class, slots, `tfstate`, weapon frame, `attack_finished`,
clip/reload timers, grenade state, conc state, PRNG seeds, and optionally
pmove origin/velocity.

- Server side it is `.predict_state` on the player entity.
- Client side there are **two copies**: `pstate_server` (last authoritative
  snapshot) and `pstate_pred` (locally advanced). Every prediction pass starts
  with `pstate_pred = pstate_server` and re-derives forward.

Replication is a dirty-mask delta. `Prediction_ChangedMask()` compares field
groups with the `M1`..`M4` macros, sets `FOWP_*` bits, and additionally rotates
one "forced refresh" bit per frame between `FOWP_FIRST_PERIODIC` and
`FOWP_LAST_PERIODIC` so any silently-diverged field self-heals within a cycle.
`TFL_SendPredictState` / `TFL_RecvPredictState` are the *same function body*
compiled twice — the `COMM(type, field)` macro is a `Write*` on the server and a
`Read*` on the client. **Adding a field means touching the mask enum, the
`M*` comparison list, and the `COMM` block, in that one file.**

Transport is `SVC_CGAMEPACKET` + a `MSG_*` id (`MSG_PREDICTSTATE`,
`MSG_TFL_CONFIG`, …), dispatched client-side in `csqc/events.qc`.

### Time bases

There is **one** server clock. `time` is it, on both sides (CSQC `time` tracks
server time closely enough that `phys_time` is compared against it directly).
A separate `.client_time` field existed until it was collapsed away; if you see
it referenced in old branches or patches, it was `time` minus a per-client
epoch, and everything it did is now done by `time`.

Two derived clocks remain:

- `remote_time()` (`ssqc/time.qc`) — `time` pulled back by the client's ping
  (capped at `tf_config.max_rewind_ms`), forced monotonic via
  `.last_remote_time` so lag correction can never reorder events that `time`
  would not. `bounded_remote_time(dt)` floors it at `time - dt`.
- CSQC `interp_time()` — monotonic local clock advanced by `pred_time_dt`,
  matching how far remote players have been extrapolated, so predicted
  projectiles collide against the same world the player sees.

Also on the client, don't confuse the *field* `pstate_pred.server_time` (the
server's clock, advanced by `input_timelength` per replayed input frame) with
the *function* `server_time()` in `weapon_predict.qc` (local `time` plus
frames-ahead). They are different quantities with nearly the same name.

#### The think warp

Player animation runs on a parallel think system — `.client_think` /
`.client_nextthink`, set via `FO_SetClientThink(func, offset)`
(`share/animate.qc`) — rather than the engine's `.think`/`.nextthink`. The
reason is networking: `client_nextthink` and `client_thinkindex` are part of
`predict_tf_state` and ship in `FOWP_THINK`, so CSQC can replay the same FSM.
`.nextthink` is engine-private and invisible to CSQC.

`FO_CheckClientThink` (`ssqc/time.qc`, called from `PlayerPostThink`) warps
global `time` to `client_nextthink` for the duration of the think, then
restores it — deliberately mirroring what the engine's `SV_RunThink` does for
`.think`, and what `FO_CustomPhysics` already does for projectile thinks.
`WP_Frame` (`csqc/weapon_predict.qc`) warps `pstate_pred.server_time`
identically. **Both sides must warp or weapon timing desyncs.**

Consequences worth knowing before you touch it:

- Anything reachable from a client_think sees `time` up to one frame early
  (≤ ~13 ms at 77 fps, always early, non-accumulating since each warp
  re-anchors to the exact schedule). That reach is not small: `axe_extra`
  dispatches to `W_FireAxe`/`Knife`/`Medikit`/`Spanner`, and the spanner path
  reaches `AttemptToActivate`, `DoResults` and the engineer building code.
- The dangerous pattern is a value written *outside* the warp at real `time`
  and read *inside* at warped `time` — a same-frame debounce would read as
  not-yet-elapsed. Known writes in the reachable set are all
  `nextthink = time + delay` scheduling, which is safe.
- `Attack_Finished` and the reload timers are set inside the warp for
  fire-in-anim weapons (nailgun, SNG, assault cannon) and for reloads, which
  is exactly why the warp exists.

### Determinism: shared PRNG

Anything random that both sides must agree on draws from the shared 16-bit LFSR
in `share/classes.qc` — `shared_prng(PRNG_WEAP | PRNG_MOVE | PRNG_HWGUY |
PRNG_CONC)`. The seeds ride along in `predict_tf_state.prng_base[]`. Do not
introduce `random()` into a predicted code path.

### Predicted projectiles

`fpp_types[]` (`share/prediction.qc`) describes each projectile type
(`FPP_ROCKET`, `FPP_GRENADE`, `FPP_HANDGRENADE`, …): movetype, speed, model,
trail, sound. Server projectiles carry `SendEntity = PP_SendEntity` and a
`FOPP_*` sendflags delta; the client mirrors it in `EntUpdate_Projectile` —
again one macro'd body for both directions. `ENT_CONFIG/ENT_WEAPONPRED/
ENT_PROJECTILE` are the CSQC entity classes.

Both sides run `share/physics.qc` (`Phys_Advance`) over projectiles, so a
locally spawned rocket flies the same arc as the server's.

### Lag compensation (see also `antilag.md`)

Three cooperating mechanisms, gated by `tf_config.rewind_flags`
(`REWIND_*` in `commondefs.qc`):

1. **Forward projection** — `Forward_ProjectOffset()` gives each projectile a
   fixed head start (`static_newmis_ms`, ~50ms; deliberately *not* using
   engine `newmis`, whose built-in 50ms cannot be unwound) plus a ping-derived
   `dynamic_ms` clamped by `max_rewind_*`. `Forward_Projectile()`
   (`ssqc/rewind.qc`) applies it.
2. **Rollback** — `ssqc/rewind.qc` keeps a 50-slot origin/velocity ring per
   player. `RL_RewindTo()` moves everyone back to the shooter's view of the
   world for the projection step, `RL_RestorePositions()` puts them back.
   `REWIND_PROJ_FIRE` covers spawn, `REWIND_PROJ_TRAVEL` re-rewinds each frame
   of flight inside `FO_CustomPhysics`.
3. **`sendevent` corroboration** — with `REWIND_SENDEVENT`, the client sends
   `sendevent("Attack", "ifvv", weapon, pstate_server.server_time, org, angles)`
   and the server fires from *that* position/time via `CSEv_Attack_ifvv`, with
   sanity bounds against `last_death` / `last_attack_ctime`.

Hitscan (shotguns) instead relies on engine `sv_antilag 1`.

**Rewind barriers.** `RewindBarrier(player)` stamps `RewindState.barrier` with
`time`, marking a discontinuity in that player's position history: set on death
(`PlayerDie`), on teleport (`triggers.qc`), and on spawn (`PutClientInServer`).
`RewindTo()` refuses to reposition a player for `rtime <= barrier`, because the
snapshots on the far side belong to a different place or a different life. Note
the interpolation guard `if (vlen(diff) > 48) frac = 1` resolves *toward the
newer sample*, so removing that early-out without also clamping the seek would
place teleported players at their post-teleport position — worse than not
rewinding. `localinfo rewind_barrier` (short `rwbar`, default off) additionally
god-modes players held behind their barrier so a projectile can't score a hit at
a position known to be wrong; knockback still applies, since `T_Damage` returns
on godmode only *after* the velocity push.

Two invariants in `RewindState` exist because health and god mode can change
mid-window — `Phys_Impact` runs `touch` (and so damage) inline, so the very
explosion being stepped can kill the player. `saved` latches whether
`held_origin` was captured; `save_god` latches the pre-rewind god flag. Both are
written once per stash, never re-derived at restore time, and both setters are
idempotent so the per-physics-tic `RewindTo()` calls can't clobber them.

### Player movement prediction (`fo_pmove`)

Opt-in and more invasive: the server hands position authority to the client via
a staged `Predict_SyncPmove` handshake (`PMT_ACTIVATE1` → `PMT_ACTIVE` →
`PMT_DEACTIVATE1/2`), sets `nodrawtoclient`, and the client runs
`runstandardplayerphysics()` over its own input history in
`csqc/pmove.qc:PM_RunMovement()`, replaying from the last acked frame.
Explosion knockback the client cannot know about arrives as *nudges*
(`PM_AddNudgeExplosion` / `PM_AddNudgeBounce` / `PM_AddNudgeDash`) matched into
the replay by sequence and time. `PM_UpdateError()` smooths residual
divergence; `fopmd_graph` draws it.

### Client frame flow

```
CSQC_Input_Frame   → Sync_GameState, PM_InputFrame (speed clamps, smartjump)
CSQC_UpdateView    → addentities(MASK_ENGINE | WPP_ViewModelMask())
  viewmodel.predraw = WP_ClientThink        // prediction runs here
      if servercommandframe/clientcommandframe advanced:
          pstate_pred = pstate_server
          WP_ProcessServerUpdate()          // reconcile
          WP_UpdatePredict() → WP_Frame()   // re-simulate forward
              client-time thinks → WP_AnimateModel
              WP_CheckReloadFinished, WP_Impulse, WP_ExplodeGren,
              W_ThrowGren, WP_Attack, WP_Sniper_UpdateSight
      WP_UpdateViewModel, WP_PreviewSentry
  → PM_UpdateView (if pmove) → renderscene → HUD
```

Predicted sounds go through `Predicted_Sound()`, which logs into a ring buffer
so the matching server sound can be suppressed on arrival (`SndLog_Search` /
`Predictable_Sound`).

## Conventions

- Cvars: declare with `DEFCVAR_FLOAT(name, default)` in the relevant csqc file,
  read with `CVARF(name)`. Client cvars are conventionally `fo_*` / `tf_*` /
  `wpp_*` / `fopm*`.
- Server config: `CF_GetSetting("short", "long_name", "default")` reads
  `localinfo`; `FO_GetUserSetting(ent, …)` reads a player's `setinfo`. Both
  accept `on`/`off` as well as numbers.
- Debug: `printf`/`printd` (`share/debug.qc`) work in both VMs;
  `ASSERTF_*` / `ASSERTD_*` compare-and-error; `PRINT_ONCE` / `PRINT_EVERY`
  for rate-limited output; `PERIODIC(p)` / `STATIC_INIT_ONCE()` helpers.
- Style is C-like with 4-space indent in the newer (`share/`, `csqc/`,
  prediction-adjacent) code. Older inherited TF files (`tfortmap.qc`,
  `misc.qc`, `doors.qc`, …) keep original QuakeC style — `local` declarations,
  `void () Name = { … }`. Match the file you are editing.
- Commit messages are `area: lowercase summary` (`rewind: properly destroy
  state on disconnect`, `eng: fix cases where impeller would mistarget`).
- Work happens on `staging` / `dev-cur`; `main`/`master` is the release branch.
  The repo also carries stgit-style topic branches.

## When changing predicted behaviour

Any gameplay change to weapons, grenades, reloads, animations, movement or
projectiles has to land on **both** sides or the client will visibly rubber-band:

1. Prefer putting the logic in `share/` behind `#ifdef` accessors rather than
   duplicating it in `ssqc/` and `csqc/`.
2. New state the client must know about goes into `predict_tf_state` **and**
   into `Prediction_ChangedMask` **and** the `COMM` block.
3. New tunables go into `TMPL_CONFIG_DATA` plus a `CONFIG_UPDATE` entry in
   `TflCheckConfigUpdate` (`share/prediction.qc`).
4. Randomness uses `shared_prng`, never `random()`.
5. Time comparisons in predicted code use `time` on the server and
   `pstate_pred.server_time` on the client. Both are warped inside a
   client_think — see **The think warp**.
6. If the behaviour genuinely cannot be predicted yet, either suppress
   prediction for that window (`filter_pproj_time`, `FPF_NO_REWIND`,
   `Predict_AddFilterEnt`) or leave it `NO_PREDICT` in `weapon_info[]`.

## CSQC shaders and inline GLSL

`shaderforname(name, body)` builds a shader from a QC string, and the body may
contain a `program { }` block with GLSL written inline — so custom shaders and
GLSL both ship inside `csprogs.dat` with **no client package or pak**. All of
the below was established empirically against this engine build; none of it is
in the FTE docs in-tree, and most of it is invisible from the rendering.

**Use `developer 1`.** GLSL compile errors print there and name the failing
symbol. Every one of these was found in a single round that way, after several
rounds of guessing from what appeared on screen got nowhere.

Confirmed symbols after `#include "sys/defs.h"`: `ftetransform()`,
`m_modelviewprojection`, `v_normal`, `e_colourident` (entity colour, driven by
`.colormod`), `e_eyepos`.

Traps, all of which fail silently or misleadingly:

- **`v_position` is a `vec4`.** Adding a `vec3` to it gives "could not
  implicitly convert operands to arithmetic operator", and the rest of the
  function then reports cascading "used uninitialized" noise.
- **`ftetransform()` applies the alias-model frame blend; transforming
  `v_position` by hand does not.** Do the latter and the effect detaches from
  the model as it animates. Raw attributes are still fine for deriving a
  *direction*, where being a frame stale is not visible.
- **`%g` in a `sprintf`'d shader emits `1` for a whole number**, which GLSL
  reads as an `int` and refuses to multiply against a `float`. Always `%f`.
- **`!!cvarf <name>` does not produce a `cvar_<name>` uniform.** Live cvars in
  a program need the real naming convention found first; baking the value into
  the source and rebuilding on change is the workaround.
- **Translucency is unreachable with a `program` block.** `blendfunc` in the
  shader body is ignored, and entity `.alpha` does not force a blended pass
  either — so appearance has to be expressed in the fragment output, and
  soft/antialiased edges are not available.
- **`!!samps <name>` declares samplers**, the way `!!permu` declares
  permutations; `s_diffuse` does not exist until `!!samps diffuse` asks for it.
  Treat every `!!` line as an opt-in declaration rather than a hint.
- **`deformVertexes` does not apply to alias models** — only BSP surfaces. It
  appears to work as an on/off but never scales with its amount. Vertex
  displacement on players has to happen in a program.
- **`/* */` comments inside a `program` block are fine.** An earlier note here
  claimed they silently break the body; that was wrong. The GLSL in
  `SilhouetteShader` (`csqc/tfx.qc`) carries one and compiles and renders
  correctly. The silent-fallback symptom that produced the claim -- the effect
  keeps drawing but stops responding to the program -- is real, but its actual
  cause is the `shaderforname` name cache below. Comments outside the
  `program` block, in the shader script proper, are still untested.
- **`shaderforname` caches by name on the client.** Confirmed deliberately:
  requesting an already-seen name with a *different body* changes nothing,
  while changing the name takes effect immediately. So a name reused across
  edits keeps returning the first version compiled, broken or not — which
  convincingly mimics "my change did nothing" and will burn several debugging
  rounds if you do not know it. `rnds()` in `csqc/tfx.qc` exists for exactly
  this and is normally left behind `#if 0`. Suffix shader names while
  iterating; before shipping, use a fixed name and bump it by hand whenever
  the body changes.

Also note `AddOutline` in `csqc/tfx.qc` is immediately followed by `#if 0`
covering `UpdateOutline` and the x-ray outline path, so code added there
compiles away silently.

## Known rough edges

Verified by reading the code, not by running it. Worth knowing before you trust
something or "fix" it.

- **The CSQC profiler is inert.** `csqc/profile.qc` has a complete sampling
  harness and three samplers are declared and `INIT_*`'d in `CSQC_Init`, but
  `perf_start_sample` / `perf_finish_sample` have **no callers**. So the
  `perf_status` console command prints zeros and `fo_enable_profiling` does
  nothing. Wire these up before doing any CSQC performance work — the
  per-frame paths are otherwise already well optimised (HUD render cache with
  incremental one-panel-per-frame redraw, batched string-cvar caching,
  `kRenderDt` limiters on viewmodel and sentry preview, `Phys_Sim` gated to
  `SERVER_FRAME_DT`).
- **`cvar("sv_gravity")` in the physics inner loop** (`share/physics.qc:108`,
  called from `Phys_Adv_Bounce`) — a string-keyed lookup once per 5 ms
  `phys_tic` per bouncing projectile, on both server and client. Same for
  `cvar("sv_gameplayfix_grenadebouncedownslopes")` on each bounce. Hoistable.
- **`.attack_finished` means three different things** depending on entity
  class: a player's weapon cooldown; a map entity's / monster's debounce
  (`doors.qc`, `plats.qc`, `rotate.qc`, `triggers.qc`, `subs.qc`); and on map
  items a *goal number* (`tfortmap.qc:1663` does `Findgoal(Item.attack_finished)`).
  The populations are disjoint today. The exposure is the writes through
  `.owner` in `doors.qc` / `rotate.qc`, which would land in the wrong meaning if
  ownership ever pointed at a player.
- **Dead code**: `TFxRenderGrenadeTimers` (`csqc/tfx.qc`) is unreachable behind
  a leading `return;`, so team grenade timers don't render; `UpdatePlayer`
  (`csqc/tfx.qc`) is never registered — only `CSQC_UpdatePlayer` is passed to
  `deltalisten`; `FOPlayer::Respawn` (`ssqc/rewind.qc`) is an empty hook nothing
  calls.
- **`deltalisten` callbacks run every frame per matching entity**, not only on
  network updates ("standard entity fields will be overwritten each frame before
  the updatecallback is called"). `CSQC_UpdatePlayer` is therefore a per-player
  per-frame hot path.

## Repo hygiene note

The working tree is littered with untracked scratch files (`.swp` files, `q`,
`tq`, `stuff`, `sage`, `\`, `:w`, …) and large stray blobs (`ound`, `ses`).
They are not part of the build — ignore them, and don't clean them up unasked.

## Further reading in-tree

- `README.md` — user-facing changelog of commands, cvars, `localinfo`/`setinfo`
  options. Update it when adding a player- or admin-visible knob.
- `antilag.md` — prose explanation of the lag compensation design.
- `docs/tfentref.txt`, `docs/tfortmap.txt` — original TF 2.9 map entity
  reference, still authoritative for `info_tfgoal` semantics.
