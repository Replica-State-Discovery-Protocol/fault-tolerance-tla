TLA2TOOLS = tla2tools.jar
JAVA_OPTS = -XX:+UseParallelGC -Xmx12g
CONFIGS   = safety_n3 safety_n4-a1 safety_n4-a2 safety_n5 detect_n3 shadow_off shadow_on shadow_recovery_n3
TLC_FLAGS =

# Defer liveness to a single pass at the end: the periodic passes re-run over
# the whole accumulated behaviour graph and cost ~20% of wall-clock at n = 4.
# The trade is memory — the one final pass needs the complete graph at once.
safety_n4-a2: TLC_FLAGS = -lncheck final
shadow_recovery_n3: TLC_FLAGS = -lncheck final

.PHONY: all $(CONFIGS) clean

all: safety_n3 detect_n3 shadow_off shadow_on

$(TLA2TOOLS):
	curl -sL -o $@ https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar

$(CONFIGS): %: $(TLA2TOOLS)
	cp models/$*.cfg spec/rsdp.cfg
	cd spec && java $(JAVA_OPTS) -cp ../$(TLA2TOOLS) tlc2.TLC -workers auto $(TLC_FLAGS) -config rsdp.cfg rsdp.tla
	rm -f spec/rsdp.cfg

clean:
	rm -rf spec/states spec/rsdp.cfg states *.out
