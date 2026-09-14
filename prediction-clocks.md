Explosion Prediction and Clocks
===============================

How the client and the server come to the same answer about an explosion: how
hard it pushed you, from where, and on which of your movement commands.

The problem
-----------

The client predicts its own movement, replaying the commands the server has not
acknowledged yet. When a grenade goes off nearby, the client has to apply the
push during that replay, before the server tells it anything. The server applies
its own push independently. If the two disagree, the correction arrives a round
trip later and the view lurches.

Two things have to match.

**Which command the push lands on.** This is a discrete choice, so there is no
such thing as a small error in it. Being four milliseconds out is not four
milliseconds of push in the wrong place, it is a whole command, which at typical
speeds is around twelve units of position.

**Which position the blast is measured from.** Range, line of sight, damage
falloff and the push direction all read from the player's position. Measuring
from two different positions gives two different pushes.

The three clocks
----------------

### Command clock

Per player, server-side, built in `CmdClock_Update` (ssqc/client.qc). Each
command's clock value is the previous one plus that command's `input_timelength`.
It is re-anchored to real server time only when the two have drifted more than
50 ms apart.

The client rebuilds the identical chain: it takes the value echoed in its
predict state for the last acknowledged command and extends it with the same
frame lengths. Because both sides chain the same numbers, a given command has
the same clock value on each, exactly. That is what makes it the right handle
for anything tied to a command.

It is not a world clock. In traces it sits tens of milliseconds away from real
server time and wanders, which is discussed under [Why it wanders](#why-it-wanders).

### Projectile physics clock

Per projectile, and deliberately not shared. The server runs a projectile on
real server time, which is why it can hand `phys_time` straight to the engine's
`rewindworld`. The client runs its own projectiles on `interp_time()` so they
collide in line with what the player is shown, and runs other players'
projectiles further ahead still, by up to the ping, so they sit where they will
be when they arrive. The comment on `get_phys_time` (csqc/weapon_predict.qc)
says outright that this "will offset explosions in the short term".

Its absolute value means something different on each side. The elapsed time a
projectile has been in the air is the same quantity everywhere, and that is the
only way this clock is allowed to cross to the others.

### Absolute server time

Real time on the server, reachable as `RealTime()` or `cmd_real_time` inside the
command warp. Every world event has an absolute instant, and that instant is the
same fact for everybody. A grenade's fuse (`fpp.expires_at`) and a rocket's
impact (`impact_phys_time`) are both stamped here.

How a push is scheduled
-----------------------

### Hold it for the command it was due on

A blast goes off in the server's physics phase, between two commands. Which
command runs next is down to when the player's packet happens to arrive, so
applying the push immediately puts it on a command the client cannot predict.

Instead every blast's push is held on the victim's `pending_knock` list with a
due time, and `PlayerKnock_Apply` (ssqc/weapons.qc) releases it from
`PlayerPostThink` on the first command whose clock has reached that time. The
client's nudge window is the same predicate: `MatchNudge` fires an explosion
nudge on the frame whose window `(start, end]` contains the due time, applied
after that frame's move.

Three kinds are held:

- `KK_SELF_PROJ` — the shooter's own push from their own projectile. The
  original case, and the one that always agreed.
- `KK_BLAST` — one target's push from a world blast, a grenade or a rocket.
- `KK_BOUNCE` — one target's conc launch. Held separately because a conc
  assigns velocity outright rather than adding to it, so its direction is the
  whole of the effect.

Health damage is not held. It lands where the blast found you. Only the push
moves, which is what the client is predicting.

### Measure it from where the command left you

Both sides evaluate the blast against the position the due command left the
player in. The server is standing there when it releases the held push; the
client is at the same place at the end of the frame it applies the nudge on.
Neither looks anything up.

### Find the due time without converting anything

For the shooter's own projectile the due time is `fire_cmd_time` plus the
projectile's travel, computed in `AntilagKnock`. Both sides hold the fire
command's clock identically, so nothing is converted and the two agree to a
fraction of a unit. A projectile that reaches what it hit inside the frame it
was fired lands on the fire command itself; the client mirrors the same
threshold of one server frame.

For everyone else's blast the due time is on the victim's command clock, and
the absolute instant has to be brought onto it. That crossing is the hard part.
See the next section.

Why it wanders
--------------

The command clock does not run fast. Measured within a single anchor epoch:

| span | clock error |
| --- | --- |
| 405 commands over 13.20 s | −1.6 ms |
| 292 commands over 9.16 s | −0.3 ms |
| 90 commands over 10.32 s | −2.8 ms |
| 131 commands over 2.42 s | **+16.1 ms** |

Three stretches of ten seconds or more hold to under 0.03 percent, then one
gains 16 ms in under two and a half seconds. It is not a rate error and not the
client's crystal. It wanders in bursts, because the chain advances by each
command's own length while the server's clock advances once per frame. A burst
of queued commands walks the offset forward, a sparse patch walks it back, and
the 50 ms guard clamps the walk.

So the offset between the command clock and absolute time is a random walk with
a hard reset, not a drift. Two samples of it taken a round trip apart differ by
a few milliseconds, and near a frame edge a few milliseconds is a whole command.

Current mitigation, and why it is temporary
-------------------------------------------

Each projectile that can push someone takes one reading of every player's
command clock when it is created (`Proj_StampViewers`, share/prediction.qc) and
sends each player only their own, under `FOPP_CMDBASE`. Everything after that is
elapsed time: what is left of a fuse, or how long a rocket has been in the air.
Neither side converts an absolute instant, so neither can be caught holding a
stale sample of the offset.

This is a workaround for the clock having a step in it, not part of the intended
design. It has two known weaknesses:

- A re-anchor during the projectile's life moves what the frozen reading means
  in real terms, by up to 50 ms. Both sides stay in agreement, so prediction
  stays exact, but the push can land noticeably after the explosion is drawn.
- It costs a per-viewer array on every projectile that can knock, and it only
  covers projectiles. Anything the server raises on its own falls back to
  converting with the live offset.

The intended design
-------------------

The command clock's job is to work out when a player actually primed or fired,
on their own timeline. That is lag compensation and it belongs server-side. Its
output is an instant, and that instant is then stamped in absolute server time,
once, for everyone including the player who caused it. Nothing downstream is
expressed in anyone's command clock.

For that to work the client has to turn an absolute instant into one of its own
commands, and get the same answer the server does. That holds if and only if the
two chains produce identical values for every command. Today they can differ,
because the server snaps its chain at a moment the client has not heard about
yet.

So the keystone is **publishing chain corrections ahead of the commands they
apply to**, in the form "from sequence N onward the chain shifts by this much",
sent far enough in advance that the client always has it before it predicts
those frames. The client leads by around eight commands and the round trip is
about the same, so naming a sequence thirty or so ahead leaves ample margin. The
server then commits to what it published rather than recomputing.

With that in place:

- The two chains are provably identical, so an absolute stamp converts the same
  way on both sides.
- The correction threshold can be tightened well below 50 ms, so the chain
  tracks absolute time closely instead of wandering.
- The per-viewer reading comes out, and explosions schedule against the absolute
  expiry with nothing carried per projectile.

This changes a clock that projectile fire timing and the replay windows already
depend on, so it wants landing deliberately rather than folded into other work.

Measuring it
------------

`localinfo pm_debug 1` turns on the prediction journal. For each command the
server records where it left the player and what happened along the way, and
sends it to that player, who holds the same record from its own prediction and
reports divergences with the frames leading up to them. The client half is
csqc/pmdebug.qc, the server half ssqc/pmdebug.qc.

Progress across the work described here, on comparable runs:

| | frames | missed | worst position |
| --- | --- | --- | --- |
| before | 1900 | 10 (0.5%) | 13.60 u |
| after | 2131 | 2 (0.1%) | 0.01 u |

Known gaps
----------

- A blast the server raises on its own, rather than from a projectile, carries
  no reading and converts with the live offset.
- A player who was not connected when a projectile appeared has no reading for
  it and falls back the same way.
- The client cannot see brush entities when judging whether a blast reached it.
  The server clips against them; the client's trace is world-only.
- Mirv cluster grenades are never spawned client-side, so their blasts are not
  predicted at all.
- Grenades bounce off players on the server and pass through them on the client,
  which has no players in its trace world.
