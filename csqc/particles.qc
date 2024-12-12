static string gas_p[] = {
"r_part gas_smoke_base\
{\
	texture \"particles/smoke.tga\"\
	count 75\
	scale 30\
	scalerand 10\
	alpha 0.4\
	die 1.5\
	diesubrand 1\
	randomvel 10\
	veladd 0\
	rgb 55 125 30\
	gravity -5\
	blend add\
	spawnorg 175 50\
	spawnvel 0 0\
	assoc gas_smoke\
	scalefactor 1\
	scaledelta 20\
	up 40\
	rampmode delta\
	ramp 0 0 0 -0.5\
	ramp 0 0 0 -0.5\
	ramp 0 0 0 0.6\
	ramp 0 0 0 0.6\
}\n",
"r_part gas_smoke\
{\
	texture \"particles/bloodsplat2.tga\"\
	count 55\
	scale 60\
	scalerand 60\
	alpha 0.8\
	die 3\
	randomvel 60\
	rgb 20 255 20\
	diesubrand 1\
	friction 1\
	gravity -5\
	spawnorg 100 0\
	spawnvel 60 60\
	blend modulate\
	emit gas_smoke_e\
	emitinterval 1\
	emitintervalrand 1\
	scalefactor 1\
	up 40\
}\n",
"r_part gas_smoke_e\
{\
	texture \"particles/round.tga\"\
	count 2\
	scale 90\
	scalerand 40\
	alpha 0.1\
	die 3\
	randomvel 15\
	veladd 0\
	rgb 22 66 22\
	diesubrand 1\
	friction 0.2\
	gravity -5\
	spawnmode circle\
	spawnorg 10 10\
	clipcount 1\
	cliptype nothing\
	blend add\
	scalefactor 1\
	rampmode delta\
	ramp 0 0 0 -0.2\
	ramp 0 0 0 -0.2\
	ramp 0 0 0 -0.2\
	ramp 0 0 0 0.2\
	ramp 0 0 0 0.3\
	ramp 0 0 0 0.4\
}\n"};

static string sentry_p[] = {
"r_part sentry_radius_max\
{\
	texture \"particles/flare2.tga\"\
	count 200\
	scale 8\
	scalefactor 0\
	alpha 0.8\
	die 0.5\
	diesubrand 0.2\
	rgb 255 50 50\
	friction 0 0 1\
	spawnorg 1000 0\
	spawnmode circle\
	clipcount 0\
};\n",
"r_part sentry_radius_fast\
{\
	texture \"particles/flare2.tga\"\
	count 100\
	scale 8\
	scalefactor 0\
	alpha 0.4\
	die 0.5\
	diesubrand 0.2\
	rgb 255 255 50\
	friction 0 0 1\
	spawnorg 500 0\
	spawnmode circle\
	clipcount 0\
};\n"};

void Register_Particles() {
#if 0
    localcmd("wait\nwait\nwait\n");  // Synchronizes some unknown race
#endif
    localcmd(gas_p[0]);
    localcmd(gas_p[1]);
    localcmd(gas_p[2]);
    localcmd(sentry_p[0]);
    localcmd(sentry_p[1]);
}

