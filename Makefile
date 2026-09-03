ifndef VER
    VER := $(shell ./version.sh --version)
endif

ifndef REV
    REV := $(shell ./version.sh --revision)
endif

# Suffix for shader and particle effect names.  A client can redefine either by
# name -- "r_part gas_smoke_base { alpha 0 }" to see through spy gas, or
# nodepthtest on an outline shader for a wallhack -- so the names rotate.
#
# Hashing the client sources rather than using REV means the names change when
# the client code changes and not on every commit: often enough that an override
# does not survive, rarely enough that shaderforname's by-name cache still hits
# within a build.  One variable, passed to both progs, so the server derives the
# same particle names the client defines.
# $(sort $(wildcard ...)) rather than a shell glob: shell expansion order
# depends on collation, so the same tree hashed under a different locale gave a
# different value.  make's sort is plain byte order and does not.
PHASH_SRC := $(sort $(wildcard csqc/*.qc share/*.qc))
ifndef PHASH
    PHASH := $(shell cat $(PHASH_SRC) | md5sum | cut -c1-8)
endif
ifeq ($(strip $(PHASH)),)
    PHASH := $(REV)
endif

all:
	fteqcc64 -DVER=\"$(VER)\" -DREV=\"$(REV)\" -DPHASH=\"$(PHASH)\" -DLOGIN_SALT=\"$(LOGIN_SALT)\" ./ssqc/progs.src
	fteqcc64 -DVER=\"$(VER)\" -DREV=\"$(REV)\" -DPHASH=\"$(PHASH)\" -DLOGIN_SALT=\"$(LOGIN_SALT)\" ./csqc/csprogs.src
	fteqcc64 -DVER=\"$(VER)\" -DREV=\"$(REV)\" ./menu/menu.src

clean:
	rm -f $(TARGET) qwprogs.lno files.dat progdefs.h
