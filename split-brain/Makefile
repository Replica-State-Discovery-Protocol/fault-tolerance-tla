TLA2TOOLS = ../tla2tools.jar
JAVA_OPTS = -XX:+UseParallelGC -Xmx12g
# One worker keeps BFS exact: shortest counterexamples and the true depth, so
# the numbers in README.md reproduce. With several workers the verdict and the
# distinct-state count of a passing run are unchanged, but traces may be longer
# and the reported depth larger. Override with WORKERS=auto.
WORKERS   = 1

LEMMA     = lemma1_cap lemma1_nocap
MUTATIONS = sb_gate_off sb_agg_fresh sb_order_off sb_quar_off sb_tenure_evict \
            sb_adj_off sb_spacing_off sb_cap_off sb_rec_tight
HOLDS     = sb_full_n3 sb_merge_n3 sb_quar_on sb_tenure_fresh \
            sb_adj_on sb_spacing_on sb_cap_on sb_tie
WITNESSES = w_failover w_restart w_lateheal w_double w_tie
CONFIGS   = $(LEMMA) $(MUTATIONS) $(HOLDS) $(WITNESSES)

.PHONY: all quick $(CONFIGS) clean

# everything except the long sb_full_n3 run
quick: $(filter-out sb_full_n3,$(CONFIGS))

all: $(CONFIGS)

# The long run goes parallel: its verdict and state count do not depend on the
# worker count, only its reported depth does.
sb_full_n3: WORKERS = auto

$(TLA2TOOLS):
	curl -sL -o $@ https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar

# lemma1_* run LemmaOne.tla; everything else runs SplitBrain.tla.
$(CONFIGS): %: $(TLA2TOOLS)
	@mkdir -p logs; mod=SplitBrain; case "$*" in lemma1_*) mod=LemmaOne;; esac; \
	cp models/$*.cfg spec/$$mod.cfg; \
	cd spec && java $(JAVA_OPTS) -cp ../$(TLA2TOOLS) tlc2.TLC -workers $(WORKERS) \
	    -config $$mod.cfg $$mod.tla | tee ../logs/$*.log; \
	rm -f $$mod.cfg

clean:
	rm -rf spec/states spec/*.cfg
