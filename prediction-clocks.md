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

**Which command the push lands on.** This is a discrete choice. Getting it wrong
costs one command of velocity, so the damage scales with the frame length: about
twelve units at 17 ms, under two at 2 ms. The odds of getting it wrong scale the
other way, rising as frames get shorter, so the two effects largely cancel and a
fast client is not worse off.

**Which position the blast is measured from.** Range, line of sight, damage
falloff and the push direction all read from the player's position. Measuring
from two different positions gives two different pushes.

The two clocks
--------------

### The client frame clock

Per player. Where a shot started, in position, angles and time together. It
exists because the player acted on a frame corresponding to a past world
instant, and reconstructing that frame is the whole of lag compensation. Built
server-side in `CmdClock_Update` (ssqc/client.qc) by chaining each command's
`input_timelength` onto the last; the client rebuilds the identical chain from
the value echoed in its predict state, extended with the same frame lengths.

Because both sides chain the same numbers, a command has the same clock value on
each. That is what makes it the handle for anything tied to a command.

It is consumed on the server, at the moment a projectile is created, to turn the
shooter's frame into an absolute instant. Nothing downstream is expressed in it.

### The world clock

Real time on the server, reachable as `RealTime()` or `cmd_real_time` inside the
command warp. Every world event has an absolute instant and that instant is the
same fact for everybody: a grenade's fuse (`fpp.expires_at`), a rocket's impact
(`impact_phys_time`).

### What is not a third clock

A projectile's physics clock looks like one but is not. On the server it *is*
world time, which is why it can be handed straight to `rewindworld`. On the
client it is world time plus a display offset: `interp_time()` for your own
projectiles, and up to a ping further ahead for other players', chosen so they
collide where the player is being shown them. The comment on `get_phys_time`
(csqc/weapon_predict.qc) says outright that this "will offset explosions in the
short term".

So its absolute value means something different on each side. Elapsed flight
time is the same quantity everywhere, and that is the only way it may cross to
the other clocks.

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

- `KK_SELF_PROJ` — the shooter's own push from their own projectile.
- `KK_BLAST` — one target's push from a world blast, a grenade or a rocket.
- `KK_BOUNCE` — one target's conc launch, held separately because a conc assigns
  velocity outright rather than adding to it, so its direction is the whole of
  the effect.

Health damage is not held. It lands where the blast found you. Only the push
moves, which is what the client is predicting.

### Schedule it past the chain's lead

Holding can only ever delay a push. It cannot release one on a command that has
already run, and that is the case that kept costing us. The chain sits a few
milliseconds ahead of the world clock, so the command whose window covers the
due time can run *before* the fuse actually goes off. The client, which predicts
the fuse, schedules there regardless, and the server finds the push waiting one
command too late.

The trace caught it cleanly. The server released on command 2061 with the due
time 13.11 ms inside it; frames were 13 ms, so its clock for 2060 was already
0.11 ms past the due time and it would have released there had the push existed.

So both sides add `KNOCK_LEAD` to the due time, landing it on a command neither
has reached. They add the same amount, so they still agree on which command, and
the push arrives a little after the blast, which is under what anyone can
perceive.

It is one server frame, derived rather than picked. The commands already run in
the frame a blast goes off in carry chain clocks up to that frame's world time
plus the player's skew, and the blast is somewhere inside that frame, so the
worst case is exactly a frame. Four milliseconds could not cover it: six
grenades in seven agreed and the seventh -- the one whose due landed 3.90 ms
into its command, inside the blast's own frame -- was a command apart.

What the lead cannot cover is a burst. The chain runs ahead of the world clock
by however much command time the server has buffered for that player, and when
a packet carrying several commands runs in one frame the chain leaps while the
world does not. A blast queued just after finds the due already behind it. That
is about eight per cent of deferred pushes, it is unbounded in principle, and no
constant fixes it -- which is why the next section matters more than this one.

### Measure it at the instant it was due

Both sides evaluate the blast against the player's position at the moment the
push was due, stepping back from the end of their command by how much of it had
already elapsed. They step back from their own numbers -- the origin and
velocity that command left them with, which the journal shows agreeing to a
hundredth of a unit -- so the two answers are the same even when the commands
are not.

That is what makes a disagreement survivable. Measuring at the end of the
command instead meant landing a command apart changed *what* the push was: on a
grenade jump the target is standing more or less on the blast, so a few units of
travel swings the direction through a large angle and moves them along the
falloff at once. The two sides once came out with 333 and 80 of upward push from
the same blast. Now a mismatch costs only *when* the push lands; the vectors
agree to under a percent, measured on the failures themselves.

The step back is first order, and deliberately so. The server could ask
`laggedorigin` for an exact answer and the client cannot, and two methods that
disagree by a fraction of a unit are worse here than one approximation both
sides share exactly.

### Find the due time without converting anything

For the shooter's own projectile the due time is `fire_cmd_time` plus the
projectile's travel, computed in `AntilagKnock`. Both sides hold the fire
command's clock identically, so nothing is converted and the knocks come out
matching to every digit the trace prints. A projectile that reaches what it hit
inside the frame it was fired lands on the fire command itself; the client
mirrors the same threshold of one server frame.

For everyone else's blast, each projectile that can push someone takes one
reading of every player's command clock when it is created
(`Proj_StampViewers`, share/prediction.qc) and sends each player only their own,
under `FOPP_CMDBASE`. Everything after that is elapsed time. Neither side
converts an absolute instant, so neither can be caught holding a stale sample of
an offset that moves.

That reading is of the *instant* the projectile appeared, not of the player's
last command clock. For a projectile created inside a command warp the two are
the same, because it is created at that command. For one created from a think --
a held grenade materialising between commands -- the last command has already
run, and recording it meant the client measured the blast from a boundary in the
past while the server measured from the creation instant. Identical due times,
releases one and two commands apart, the client early every time, and worse the
shorter the commands got.

A held grenade has a second anchor available and uses it: the prime is an
impulse on a command, so `last_prime` is recorded on the holder's own clock and
`last_prime + GREN_FUSE` is the blast instant on that clock. Both sides name the
same command for it with nothing sent per grenade. The grenade is materialised
on that command too, stepped back to the fuse instant, so the two copies start
their hundred milliseconds of falling from the same place.

The chain against the world clock
---------------------------------

The chain is not a world clock and does not try to be. The gap between them is
mostly not error:

- **A quantisation floor.** A command waits for the next server frame before it
  runs, so the gap carries a sawtooth a server frame plus a command length wide.
  Measured, the error sat at +1.3 ms with 12–13 ms commands and +5 ms with
  16–17 ms commands, moving with the command length as the floor predicts.
- **Not a rate error.** The client's own timestamp tracked real server time to
  1.0 ms over 32.7 seconds, three thousandths of a percent.

`CmdClockTol` therefore sizes the correction threshold to the floor rather than
naming a number, floored at 50 ms. Correcting inside the floor would chase frame
boundaries and feed their jitter into the chain, which is the one thing the chain
exists to keep out of the replay.

When a correction is needed it is **announced before the command it applies to**,
`CMD_CLOCK_LEAD` commands ahead, so the client folds the same amount into the
same place and the two chains stay identical. Snapping the moment the server
noticed would move commands the client had already predicted. Above
`CMD_CLOCK_SNAP` the chain is not wandering, something stopped, and it snaps
instead: after a gap that size there is nothing in flight to disagree about.

The engine already detects a client whose claimed command time genuinely runs
against real time. `SV_RunCmd` accumulates each client's msec, compares it
against elapsed scaled by `sv_cheatpc`, warns, and drops them after two strikes.

Measuring it
------------

`localinfo pm_debug 1` turns on the prediction journal, on by default. For each
command the server records where it left the player and what happened along the
way and sends it to that player, who holds the same record from its own
prediction and reports divergences with the frames leading up to them. The
client half is csqc/pmdebug.qc, the server half ssqc/pmdebug.qc.

Read the position column, not the count. The count measures how often the two
sides disagree for a single frame; because the client re-predicts from the
server's state every snapshot, a one-command velocity disagreement is corrected
before it integrates into a move. The position column is what a player feels.

Progress across the work described here:

| | frames | missed | worst position |
| --- | --- | --- | --- |
| before | 1900 | 10 (0.5%) | 13.60 u |
| after the deferral and the stamp | 2131 | 2 (0.1%) | 0.01 u |
| at 12–13 ms commands | 1888 | 4 (0.2%) | 0.01 u |

Four columns are worth reading on a blast, and each answers a different
question that the others cannot:

- **edge** — how far into its command the due landed. The two sides printing
  the same edge means they chose the same command.
- **slack** — the smaller of that and what is left of the command, so how close
  the due came to deciding the other way. A due sitting 0.17 ms from a boundary
  and both sides still agreeing is what bounds the arithmetic difference between
  them; ties are not what has been going wrong.
- **reach** — how far the target's chain still had to go when the knock was
  queued. Negative means the command the client will choose has already run and
  nothing downstream can reach it: that is the burst, and it is a different
  problem from a tie.
- **anchor** — whether the due hung off the per-viewer base, where both sides
  evaluate the same expression from the same sent number, or off the world-time
  fallback with a live skew.

A mismatch is only a tie if `reach` was positive and the anchor was the base.
Otherwise it is one of the structural cases and wants fixing rather than
tie-breaking. Three runs were spent guessing between them before these existed.

Trials run as separate builds with fixed parameters rather than settings dialled
on a live server, so a log is never recorded under a value nobody remembers
setting. `KNOCK_LEAD` is printed on every release for that reason.

Backstops
---------

Anything scheduled on a player's command clock can only be released while that
player is sending commands -- naming their command is the point of the chain,
and there is no command to name without them. A think fires on the server's
clock whatever the player does; a release does not.

That is invisible in play and matters the moment the command stream stops.
`cmd_clock` is not cleared when a player goes quiet, so a schedule waiting on it
waits forever. Each of these therefore carries a backstop on the world clock:

- a deferred push holds `nextthink = RealTime() + 1` on its knock proxy;
- a held grenade's prime timer waits `GREN_BACKSTOP_WAIT` past the fuse for
  `PlayerGren_Apply`, polling every `GREN_BACKSTOP_POLL`, then detonates it.

Half a second is sized against what it covers rather than tuned: a holder whose
commands are running is released within a command or two, so it never fires for
them. What has to fit under it is a gap in the command stream. It says so when
it does fire, because a backstop carrying normal play is a bug in the thing it
is backing rather than a number to retune.

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
- A burst -- several of a player's commands arriving together and running in one
  frame -- can put the chain past a blast's due before the knock is queued. The
  server then cannot reach the command the client chose. About eight per cent of
  deferred pushes, unbounded in principle, and no lead covers it. It costs the
  timing of the push and not its direction, because both sides measure at the
  due instant. The cures all cost more than that: scheduling at creation needs
  the damage scaling a hundred milliseconds early, and a larger lead delays
  every push to catch one in twelve.
- Thrown grenades are not predicted at all. `REWIND_GRENADES` is not in
  `REWIND_DEFAULT_FLAGS`, so `W_ThrowGren` returns on its first line and the
  push arrives only from the server's copy -- an unpredicted grenade jump, which
  is the no-prediction baseline rather than a mispredicted one.
- The client's own predicted nudge for a held grenade never fires. The server's
  copy replaces the predicted entity, `PM_RemoveSelfNudges` retires the nudge,
  and the push comes from the server-sourced one a frame or two later. Long
  standing, and invisible at the pings measured because the copy arrives in
  time; at higher ping it is what the prediction is for.
