#define PHYS_DEBUG 0

static const float phys_tic = 0.005;

.float phys_time;  // Current physics time
.float impact_phys_time;  // phys time of the impact whose .touch is running, else 0

enumflags {
    PHYSF_CONSUME_ALL,
    PHYSF_REWIND_PLAYERS,         // server: resolve players at each step's time from the engine's history
    PHYSF_REWIND_EXCLUDE_OWNER,   // ...but leave the owner live (the fire forward)
    PHYSF_FAIL_STARTSOLID,
    PHYSF_SIM,
};

#ifdef SSQC
// fteqw fork: the server's per-frame player history.
const float MOVE_LAGGEDTIME = 512;
void(float t) setlaggedtime = #0:setlaggedtime;
void(float t, optional entity exclude) rewindworld = #0:rewindworld;
void() restoreworld = #0:restoreworld;
vector(entity player, float t) laggedorigin = #0:laggedorigin;
.float al_proj;               // a live projectile on the integrator (Antilag_CrossCheck finds them)
.vector al_prev_origin;       // projectile: origin before its last physics frame
.vector al_cmd_prev;          // player: origin before this command
#endif

void AugmentGrenadeImpact();

#ifdef SSQC

static void Phys_Impact(entity e, float dt, float phys_flags) {
    other = trace_ent;

    if (other.solid == SOLID_NOT)
        return;

    if (pointcontents(e.origin) == CONTENT_SKY) {
        dremove_sent(e);
        return;
    }

    if (e.touch) {
        // Valid only inside this touch: an impact the engine's own flight
        // delivers later has none, and is on real time instead.
        e.impact_phys_time = e.phys_time + dt;

        // Radius damage inside the touch goes through findradius, so for a
        // rewound flight put the players where the trace found them.
        if (phys_flags & PHYSF_REWIND_PLAYERS)
            rewindworld(e.phys_time + dt, (phys_flags & PHYSF_REWIND_EXCLUDE_OWNER) ? e.owner : world);

        entity held_self = self;
        self = e;
        other = trace_ent;
        self.touch();
        self = held_self;
        e.impact_phys_time = 0;

        if (phys_flags & PHYSF_REWIND_PLAYERS)
            restoreworld();
    }

    AugmentGrenadeImpact();

#if PHYS_DEBUG
    printf("SPhys: Impact t=%0.3f pt=%0.3f [%0.3f]\n",
            time, e.phys_time + dt, e.phys_time + frametime);
    printf("Imp: e=%p e.o=%p te=%p\n", e, e.owner, other);
#endif
}

static vector get_followed_origin() {
    return self.aiment.origin;
}

static void Phys_Expired(entity e, float phys_flags) {}
#else
DEFCVAR_FLOAT(fo_phys_debug, 0);

.entity groundentity;
.float aiment_num;
.float voided;
// This projectile stopped on us, so its push is a crossing inside our own
// command rather than a blast the server had to schedule ahead of one.
.float hit_self;

.float phys_sim_last;
.float phys_sim_voided_at;
var float phys_sim_dt;

float get_phys_time(entity);
void PM_AddSimExplosion(float itime, entity ent);

static void Phys_Impact(entity e, float dt, float phys_flags) {
    other = trace_ent;
    if (other.solid == SOLID_NOT)
        return;

    // As the server's copy of this function: a projectile that ends in the
    // sky is gone, with no blast.  Ours went off against the sky brush and
    // scheduled a push the server never made.
    if (pointcontents(e.origin) == CONTENT_SKY) {
        e.voided = TRUE;
        return;
    }

    if (e.movetype == MOVETYPE_FLYMISSILE) {
        e.voided = TRUE;
        if (!e.phys_sim_voided_at)  // want only one of sim or !sim
            PM_AddSimExplosion(e.phys_time + dt, e);
    }

    AugmentGrenadeImpact();

    if (CVARF(fo_phys_debug) & 1)
        printf("CPhys: Impact t=%0.3f pt=%0.3f sim=%d [%0.3f]\n", time, e.phys_time + dt,
                phys_flags & PHYSF_SIM,
                get_phys_time(e));
}

void PM_AddGrenadeExplosion(float itime, entity ent);

static void Phys_Expired(entity e, float phys_flags) {
    e.voided = TRUE;
    if (e.phys_sim_voided_at)  // Only one of sim or !sim
        return;

    PM_AddGrenadeExplosion(e.fpp.expires_at, e);
}

static vector get_followed_origin() {
    if (!(float)getentity(self.aiment_num, GE_ACTIVE))
        return self.origin;
    else
        return (vector)getentity(self.aiment_num, GE_ORIGIN);
}
#endif

static inline float get_gravity() { return cvar("sv_gravity"); }

#define dot(v1, v2) ((vector)v1 * (vector)v2)

// Where a straight-flying projectile is at time t on its own clock.  Its path
// is a line, so this needs no simulation and no stepping -- which is what lets
// both sides ask about an instant neither of them has stepped to.
vector Proj_OrgAt(entity e, float t) {
    return e.origin + e.velocity * (t - e.phys_time);
}

// One axis of a slab test: clip the segment's [t0,t1] to the slab, or miss.
static float SlabClip(float p, float d, float lo, float hi, float* t0, float* t1) {
    if (fabs(d) < 0.0001)
        return p >= lo && p <= hi;

    float a = (lo - p) / d, b = (hi - p) / d;
    if (a > b) {
        float t = a; a = b; b = t;
    }
    if (a > *t0) *t0 = a;
    if (b < *t1) *t1 = b;
    return *t0 <= *t1;
}

// Where along p0->p1 a segment first enters a box, if it does.
//
// Unrolled per axis.  Written as a loop over a vector subscript it compiled and
// ran and was wrong: every hit came back frac=0.000, which is the answer you get
// when only the x slab is ever consulted.
float SegBox(vector p0, vector p1, vector mins, vector maxs, float* frac) {
    vector d = p1 - p0;
    float t0 = 0, t1 = 1;

    if (!SlabClip(p0_x, d_x, mins_x, maxs_x, &t0, &t1)) return FALSE;
    if (!SlabClip(p0_y, d_y, mins_y, maxs_y, &t0, &t1)) return FALSE;
    if (!SlabClip(p0_z, d_z, mins_z, maxs_z, &t0, &t1)) return FALSE;

    *frac = t0;
    return TRUE;
}

// A player and a projectile crossing paths over one command.
//
// Both are moving, so neither can be tested against the other standing still:
// subtract the player's travel and what is left is the projectile's path
// relative to them, which for two straight segments is exact.  Both sides run
// this, over the same interval -- one command -- which is the only interval
// either of them holds both ends of.
float Proj_Crosses(vector qa, vector qb, vector pa, vector pb,
                   vector mins, vector maxs, float* frac) {
    return SegBox(qa - pa, qb - pb, mins, maxs, frac);
}

float Phys_Push(entity e, vector offset, float dt, float phys_flags) {
    float trace_flags = 0;

    if (e.movetype == MOVETYPE_FLYMISSILE)
        trace_flags |= MOVE_MISSILE;
#ifdef SSQC
    if (phys_flags & PHYSF_REWIND_PLAYERS)
        trace_flags |= MOVE_LAGGEDTIME;   // players as they were at setlaggedtime's time
#endif

    // Note: Networked entities don't currently intersect on CSQC instantiation
    // of this, we fudge this in Phys_Impact from the server side.
    traceline(e.origin, e.origin + offset, trace_flags, e.owner);


    if ((phys_flags & PHYSF_FAIL_STARTSOLID) && trace_startsolid)
        return FALSE;

    e.origin = trace_endpos;

    if (trace_fraction < 1) {
        setorigin(e, trace_endpos);
        if ((e.flags & FL_ONGROUND == 0) || e.groundentity != trace_ent)
            Phys_Impact(e, trace_fraction * dt, phys_flags);
        return FALSE;
    }

    return TRUE;
}

static float epsilon = 0.1;  // Matches ftesv
vector Phys_ClipVel(vector orig, vector normal, float overbounce) {
    float backoff = -dot(orig, normal) * overbounce;
    vector result = orig + backoff * normal;

    if (result[0] > -epsilon && result[0] < epsilon) result[0] = 0;
    if (result[1] > -epsilon && result[1] < epsilon) result[1] = 0;
    if (result[2] > -epsilon && result[2] < epsilon) result[2] = 0;

    return result;
}

float Phys_Adv_Bounce(entity e, float dt, float phys_flags) {
    float g = get_gravity();

    if (e.flags & FL_ONGROUND) {
        if (-e.velocity_z >= 1.0/32.0)
            e.flags &= ~FL_ONGROUND;
        else  // Consider falling through removed entity here at some point.
            return 0;
    }

    e.velocity_z -= 0.5 * dt * g;

    phys_flags |= PHYSF_FAIL_STARTSOLID;
    float move_time = dt, bounce;
    if (Phys_Push(e, move_time * e.velocity, move_time, phys_flags)) {
        e.velocity_z -= 0.5 * dt * g;
        e.angles += dt * e.avelocity;
        return dt;
    }


    move_time = (1 - trace_fraction) * dt;
    e.angles += move_time * e.avelocity;

    float bounce_stop = 60 / 800 * g;
    float debounce = !IsClownMode(CLOWN_RUBBERGREN) ? 1.5 : 2;
    e.velocity = Phys_ClipVel(e.velocity, trace_plane_normal, debounce);

    if (PHYS_DEBUG)
        printf("%s v=%0.3f p=%v\n", qc_prefix(), e.velocity_z, e.origin);

    float bounce_speed;
    if (cvar("sv_gameplayfix_grenadebouncedownslopes"))
        bounce_speed = dot(trace_plane_normal, e.velocity);
    else
        bounce_speed = e.velocity_z;

    if (trace_plane_normal.z > 0.7 && bounce_speed < bounce_stop) {
        e.flags |= FL_ONGROUND;
        e.groundentity = trace_ent;
        e.velocity = '0 0 0';
        e.avelocity = '0 0 0';
    } else {
        e.velocity_z -= 0.5 * dt * g;
    }

    return dt - move_time;
}

float Phys_Adv_Linear(entity e, float dt, float phys_flags) {
    Phys_Push(e, dt * e.velocity, dt, phys_flags);

    if (trace_fraction < 1)
        dt *= trace_fraction;

    e.angles += dt * e.avelocity;
    return dt;
}

static void Phys_CapVel(entity e) {
    static const float limit = 32 / phys_tic;

    if (vlen(e.velocity) > limit) {
        if (!tf_config.clown_flags)
            printf("%s v=%d too fast, consider adaptive scaling\n",
                    e.model, vlen(e.velocity));
        // normalize(e.velocity) * limit;
        e.velocity = '0 0 0';
    }
}

float Phys_Advance(entity e, float target_time, float phys_flags) {
    if (target_time < e.phys_time) {
        setorigin(e, e.origin);
        return 0;
    }

    static float limit_eps = 0.00001;
    // If there's an expiry, make sure we get to the exact position.
    if (e.fpp.expires_at && target_time >= e.fpp.expires_at) {
        target_time = e.fpp.expires_at;
        phys_flags |= PHYSF_CONSUME_ALL;
    }

    float limit = (phys_flags & PHYSF_CONSUME_ALL) ? limit_eps : phys_tic;
    float total = 0, dt = 0, step = 0, delta;

    target_time += limit_eps;
    while ((delta = target_time - e.phys_time) >= limit) {
        if (e.voided) {
            e.phys_time = target_time;
            break;
        }

        step = min(phys_tic, delta);
#ifdef SSQC
        if (phys_flags & PHYSF_REWIND_PLAYERS)
            setlaggedtime(e.phys_time + step/2);
#endif

        if (IsClownMode(CLOWN_PROJ_GRAVITY))
            e.velocity_z += -tf_config.clown_grav * step;
        Phys_CapVel(e);

        switch (e.movetype) {
            case MOVETYPE_FLY:
            case MOVETYPE_FLYMISSILE:
                dt = Phys_Adv_Linear(e, step, phys_flags);
                break;

            case MOVETYPE_BOUNCE:
                dt = Phys_Adv_Bounce(e, step, phys_flags);
                break;

            case MOVETYPE_FOLLOW:
                vector org = get_followed_origin();
                target_time = e.phys_time;
                step = target_time - e.phys_time;
                dt = step > 0 ?: 0;

                e.origin = org + e.velocity;
                break;

            default:
                printf("ERROR: %s unsupported movetype %d\n", e.model, e.movetype);
            case MOVETYPE_NONE:
                step = dt = delta;
                break;
        }

        e.phys_time += step;
        ASSERTF_LE(e.phys_time, target_time);
        total += dt;
    }

    if (step > 0)  // Origin can have moved.
        setorigin(e, e.origin);

    if (e.fpp.expires_at && e.phys_time >= e.fpp.expires_at)
        Phys_Expired(e, phys_flags);

    return total;
}

float Phys_Init(entity e, float target_time, float delta, float phys_flags) {
    if (delta > 0) {
        e.phys_time = target_time - delta;
        return Phys_Advance(e, target_time, phys_flags);
    } else {
        e.phys_time = target_time;
        setorigin(e, e.origin);
        return 0;
    }
}

#ifdef CSQC
void Phys_Sim(entity e, float target_time = 0) {
    // TODO: Unvoid+undo if we make it past the void point.
    if (e.phys_sim_voided_at)
        return;

    float min_gran = 0;
    if (!target_time) {
        if (phys_sim_dt < 0)
            return;
        target_time = time + phys_sim_dt;
        min_gran = SERVER_FRAME_DT;
    }

    if (target_time < e.phys_sim_last + min_gran)
        return;
    e.phys_sim_last = target_time;

    float held_phys_time = e.phys_time;
    vector held_org = e.origin;
    vector held_vel = e.velocity;
    vector held_angles = e.angles;
    float held_flags = e.flags;

    Phys_Advance(e, target_time, PHYSF_SIM | PHYSF_CONSUME_ALL);

    if (e.voided) {
        e.phys_sim_voided_at = e.phys_time;
        e.voided = 0;
    }
    e.phys_time = held_phys_time;
    e.origin = held_org;
    e.velocity = held_vel;
    e.angles = held_angles;
    e.flags = held_flags;
}
#endif
#undef dot
