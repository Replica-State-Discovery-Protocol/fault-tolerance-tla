# Delegates to the per-article folders. Examples:
#   make cft                    default CFT configurations
#   make split-brain            all split-brain configurations except sb_full_n3
#   make -C split-brain all     including sb_full_n3
#   make -C cft shadow_off      one configuration
.PHONY: cft split-brain clean

cft:
	$(MAKE) -C cft

split-brain:
	$(MAKE) -C split-brain quick

clean:
	$(MAKE) -C cft clean
	$(MAKE) -C split-brain clean
