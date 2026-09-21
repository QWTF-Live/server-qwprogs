FortressOne Lag Compenstation
=========
FortressOne supports lag compensation to improve player experience when playing across continents or across oceans.

tl;dr
--
```
rcon sv_antilag 1
rcon localinfo project_weapons on
```

There are two types of lag compensation available, and these are configured at the server level. 

Hitscan weapons
---------------
Enabled with: ```sv_antilag 1``` (default: 0)

Hitscan weapons are weapons where an instant trace is emitted from the attacker in the direction they are shooting. In FortressOne, this means the shotgun and super-shotgun only. 

Hitscan weapons use a rollback mechanism based on antilag support in FTE. This means that players can aim using their crosshair without compensating for latency, as it would be if they were playing on a local server.

To enable, set sv_antilag to 1.

Projectile weapons 

------------------

- Enabled with: ```localinfo project_weapons on``` (default: off)
- Configurable: ```localinfo project_weapons_max_latency``` (default: 0.1)

Projectile weapons are everything else. These are weapons which emit a projectile with a velocity that travel through space, eventually impacting on a player or the environment. 
In FortressOne, projectiles can be fast-forwarded, or 'projected' forward based on the ping of the player shooting the rocket. This means that a player on a ping with 100ms will have their projectiles origin fast-forwarded to the point that they would have spawned if the player had zero latency. 

For example:
Rockets travel at 900units / second.

A player with 0ms ping has the rocket launcher out and clicks the shoot. The server immediately receives the message and spawns the rocket. 500ms after clicking the shoot button, the rocket will be 450units away from the player. 

A player with a 100ms ping has the rocket launcher out and clicks to shoot. The server receives the message 50ms later. Without projectile fast-forwarding, after 500ms since clicking the shoot button, the projectile will be only 405units away from the player after the button was clicked - it has only had 450ms of existence and therefore 450ms of travel time. 

With project_weapons turned on, FortressOne will calculate where the rocket would be if it was spawned 50ms ago (in this case 45 units from player), and then regular handling of projectile motion takes over. 

This means that 500ms from the player clicking the shoot button, the rocket is 45 units (spawn position) + 405 (450ms * 900) units from the player position - 450 - ie, the same position had the player had 0 ping. 


Doors
-----
- Enabled with the fteqw fork's `.pusher_advance` support (always on; set `localinfo pusher_max 0` to disable)
- Configurable: `localinfo pusher_buffer` (default: 25), `localinfo pusher_max` (default: 200)

Doors, plats and trains are reported to each client advanced along their movement by that client's ping plus the buffer, capped at the max, so a player at 100ms sees a closing door where it will be when their commands reach the server -- and a little beyond, since the margin belongs on the obstructive side. An opening door is not advanced at all (`.pusher_noadvance`, set by `door_go_up`): one snapshot position serves every command the client re-predicts, and the older of those the server has already run against the less-open door, so showing it ahead put a gap on the client's screen that the server had not opened yet and the player walked into it. Held where it is, the worst case is an edge the client bumps and the server lets it through. A door about to be opened by a player's current path is additionally reported as already starting to move, hiding the round trip on the trigger; that prediction is the mod's own and still applies. The server's own door never opens early; only what each client is told changes. The predicted start is shown only to the players whose own path will trigger the door (`.pusher_predict_clientmask`); when two are heading for it, both see the earlier start, which is when it really opens if either path holds. A bystander pressing against the door would otherwise be shown a gap the server has not opened for the commands they are standing there with, and walk into it -- so nobody else is shown it, and a door somebody else opens reaches them a round trip late, which is the safe direction.

Firing before death
-------------------
- Always on with `cmd_time` (needs the fteqw fork's `.cmd_acked_time`)
- Configurable: `localinfo ghost_lockout_snapshots` (default: 1)

Commands a client generated before the snapshot carrying its death reached it are run against a copy of the player as of its last command applied alive, with the engine's player physics, so what it fired while still predicting itself alive is fired on the server too, from where those inputs put it. A command generated against one of the last `ghost_lockout_snapshots` snapshots before the death is not replayed.
