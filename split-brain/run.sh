#!/usr/bin/env bash
# Usage: ./run.sh <config> [extra TLC flags]   (config name without .cfg)
set -euo pipefail
cd "$(dirname "$0")"
JAR="${TLA2TOOLS:-../tla2tools.jar}"
[ -f "$JAR" ] || curl -sL -o "$JAR" https://github.com/tlaplus/tlaplus/releases/latest/download/tla2tools.jar
c="$1"; shift || true
mod=SplitBrain; case "$c" in lemma1_*) mod=LemmaOne;; esac
cp "models/$c.cfg" "spec/$mod.cfg"
( cd spec && java -XX:+UseParallelGC ${JAVA_OPTS:--Xmx8g} -cp "$(cd .. && pwd)/$JAR" tlc2.TLC \
    -workers auto -deadlock -noGenerateSpecTE "$@" -config "$mod.cfg" "$mod.tla" )
rm -f "spec/$mod.cfg"; rm -rf spec/states
