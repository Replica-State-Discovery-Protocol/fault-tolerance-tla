TLA2TOOLS = tla2tools.jar
JAVA_OPTS = -XX:+UseParallelGC -Xmx4g
CONFIGS   = safety_n3 safety_n4 safety_n5 detect_n3 shadow_off shadow_on

.PHONY: all $(CONFIGS) clean

all: safety_n3 detect_n3 shadow_off shadow_on

$(TLA2TOOLS):
	curl -sL -o $@ https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar

$(CONFIGS): %: $(TLA2TOOLS)
	cp models/$*.cfg spec/rsdp.cfg
	cd spec && java $(JAVA_OPTS) -cp ../$(TLA2TOOLS) tlc2.TLC -workers auto -config rsdp.cfg rsdp.tla
	rm -f spec/rsdp.cfg

clean:
	rm -rf spec/states spec/rsdp.cfg states *.out
