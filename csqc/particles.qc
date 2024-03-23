static string gas_p[] = {
"r_part gas_smoke_base\
{\
	texture \"particles/smoke.tga\"\
	count 75\
	scale 30\
	scalerand 10\
	alpha 0\
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
	alpha 0.3\
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
	alpha 0\
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

void Register_Particles() {
    localcmd("wait\n");  // Synchronizes some unknown race
    localcmd(gas_p[0]);
    localcmd(gas_p[1]);
    localcmd(gas_p[2]);
}

