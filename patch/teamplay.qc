static int kRenderStep = 13;
static var float zone_editor_active;
static var struct {
    float extend_planes;
} Debug;

static inline Map_Zones* mz() {
    return zone_state.active;
}

struct Zone_Render {
    vector color;

    // Automatic init below this line
    float effect;
};

var Zone_Render zone_render[] = {
    {'200 0 0'},
    {'200 200 0'},

    // Levels above
    {'150 150 150'},
    {'50 200 50'},
};

static void Zone_RegisterParticles() {
    // Synchronizes some race with other stuff loading
    localcmd("wait\n");

    for (int i = 0; i < zone_render.length; i++) {
        string name = sprintf("fd_boundary_%i", i);

        string pdesc = sprintf("r_part %s\
{\
	texture 'particles/fteparticlefont.tga'\
	tcoords 97 97 191 191 256\
	step %i\
	scale 10\
	alpha 0.7\
	die 1\
	rgb %v\
	gravity -450\
	randomvel 0 100\
}\n", name, kRenderStep, zone_render[i].color);
        localcmd(pdesc);

        zone_render[i].effect = particleeffectnum(name);
    }
}

static void Zone_GenerateParticles(Zone* zone) {
    int level = zone->level - zone_state->level;
    if (level < 0 || level > zone_render.length - 1)
        return;

    Zone_Render* zr = &zone_render[level];

    vector a = zone->c[0];
    vector b = zone->c[1];
    vector diff = normalize(b-a);

    if (Debug.extend_planes) {
        b += 2000 * diff;
        a += -2000 * diff;
    }

    trailparticles(zr->effect, world, a + diff * random() * kRenderStep, b);
    /* printf("%0.3f: emit: %s %d\n", time, zone->desc, zr->effect); */
}

void Zones_GenerateParticles() {
    if (!mz() || !mz()->num_zones)
        return;

    static int zone_index;
    Zone* zone = &mz()->zones[zone_index];

    if (time < zone->next_particle)
        return;

    // TODO: refactor this into something more synchronized
    if (getstatf(STAT_TEAMNO_ATTACK) == 2 != !mz()->rotated) {
        printf("ROTATING ZONES! %d\n", getstatf(STAT_TEAMNO_ATTACK));
        Zone_Rotate(mz());
    }

    zone->next_particle = time + 0.3;
    Zone_GenerateParticles(zone);

    zone_index = (zone_index + 1) % mz()->num_zones;
    if (mz()->zones[zone_index].type && !zone_editor_active)
        zone_index = 0;
};

void ZE_Init();

void CSQC_Zone_Init() {
    Zone_RegisterParticles();
    printf("CLIENT\n");
    Zone_Init();
    ZE_Init();
}

////////////////////////////////////////////////////////////////////////////////
// Zone editing
////////////////////////////////////////////////////////////////////////////////


static var Map_Zones editor_map_zones;

static var Zone zones_new[30];
static var int num_ez;
static var vector zone_v[3];
static var int last_vi;

static void CopyZone(Zone* to, Zone* from) {
    *to = *from;

    to->next_particle = 0;
}

void ActivateZoneEditor() {
    if (zone_editor_active)
        return;

    zone_editor_active = TRUE;
#if 0
    editor_map_zones.num_pz = active_mz.num_pz;
    for (int i = 0; i < num_ez; i++)
        editor_state.player_zones[i] = active_mz.player_zones[i];
    editor_map_zones.num_fz = active_mz.num_fz;
    for (int i = 0; i < num_fz; i++)
        editor_state.flag_zones[i] = active_mz.flag_zones[i];
    editor_map_zones.num_poi = active_mz.num_poi;
    for (int i = 0; i < num_poi; i++)
        editor_state.poi[i] = active_mz.poi[i];

    num_ez = zone_state.nz;
    if (num_ez) {
        for (int i = 0; i < num_ez; i++)
            CopyZone(&zones_new[i], &(zone_state.active[i]));
    }
#else
    if (zone_state->active)
        editor_map_zones = *zone_state->active;
    zone_state->active = &editor_map_zones;
#endif

    zone_editor_active = TRUE;
    printf("Zone editor active... %i zones loaded\n", mz()->num_zones);
}

void ZE_Vertex(int idx) {
    if (idx < 1 || idx > 3)
        return;

    makevectors(input_angles);
    vector org = PM_Org();
    org.z += getstatf(STAT_VIEWHEIGHT);
    traceline(org, org + 1500 * v_forward, 3, world);
    if (trace_fraction == 1)
        return;

    last_vi = idx - 1;
    zone_v[idx - 1] = trace_endpos;
}

void ZE_UpdateNearest() {
    Zone* best = __NULL__;
    vector last = zone_v[last_vi];
    float min_d = 400;

    for (int i = 0; i < mz()->num_zones; i++) {
        Zone* zone = &mz()->zones[i];
        float d = min(vlen(last - zone->c[0]), vlen(last - zone->c[1]));

        if (d < min_d) {
            best = zone;
            min_d = d;
        }
    }

    if (!best) {
        printf("No zone found\n");
        return;
    }

    printf("Updating zone '%s' (d=%0.2f)\n", best->desc, min_d);

    best->c[last_vi] = last;
}

void ZE_POI(string name, int type) {

}

void ZE_UpdateZone(string desc, int level, int type) {
    Zone* e = __NULL__;
    int i;

    for (i = 0; i < mz()->num_zones; i++)
        if (mz()->zones[i].desc == desc)
            e = &mz()->zones[i];

    if (!e)
        e = &mz()->zones[(mz()->num_zones)++];

    vector mp[2];
    mp[0] = [min(zone_v[0].x, zone_v[1].x),
             min(zone_v[0].y, zone_v[1].y),
             min(zone_v[0].z, zone_v[1].z)];
    mp[1] = [max(zone_v[0].x, zone_v[1].x),
             max(zone_v[0].y, zone_v[1].y),
             max(zone_v[0].z, zone_v[1].z)];

    e->desc = desc;
    e->type = type;
    e->level = level;
    e->c[0] = mp[0];
    e->c[1] = mp[1];
    e->c[2] = zone_v[2];

    printf("Zone %i] '%s':%i updated: [%v] [%v]\n", i, desc, level, mp[0], mp[1]);
}

void ZE_Dump() {
    printf("Preparing %i zones\n", mz()->num_zones);
    // Non-editor rendering wants this list to be ordered
    for (int i = 0; i < mz()->num_zones; i++) {
        for (int j = i + 1; j < mz()->num_zones; j++) {
            Zone* a = &mz()->zones[i];
            Zone* b = &mz()->zones[j];
            if (b->type < a->type) {
                Zone tmp = *a;
                *a = *b;
                *b = tmp;
            }
        }
    }

    printf("###\n");
    printf("  {\"%s\", %i, {\n", mapname, mz()->num_zones);
    for (int i = 0; i < mz()->num_zones; i++) {
        Zone* zone = &mz()->zones[i];
        printf("      {%i, %i, \"%s\", {'%v', '%v', '%v'} },\n",
                zone->type, zone->level, zone->desc, zone->c[0], zone->c[1], zone->c[2]);
    }
    printf("    },\n  },\n");
    printf("###\n");
}

static float Visible(vector x) {
  if ((v_forward * (x - PM_Org())) < 0)
    return FALSE;

  traceline(PM_Org(), x, 3, world);
  if (trace_fraction < 1)
      return FALSE;

  return TRUE;
}

void ZE_Debug() {
    printf("Zone debug activated\n");
    printf("Attack = %d\n", getstatf(STAT_TEAMNO_ATTACK));
    /* Debug.extend_planes = TRUE; */
}

void RenderZoneEditor() {
    if (!zone_editor_active)
        return;

    string vl[] = {"A", "B", "C"};
    for (int i = 0; i < zone_v.length; i++)
        if (Visible(zone_v[i]))
            drawstring(project(zone_v[i]), vl[i], '6 6', '1 0.2 0.2', 1, 0);

    for (int i = 0; i < mz()->num_zones; i++) {
        Zone* zone = &mz()->zones[i];

        if (!Visible(zone->c[2]))
            return;

        drawstring(project(zone->c[2]), zone->desc, '6 6', '1 1 1', 1, 0);
    }
}


float ZE_Active() { return zone_editor_active; }

static void ZE_Init() {
    /* editor_map_zones.num_zones = 0; */
    /* editor_map_zones.num_poi = 0; */
}

