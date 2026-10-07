#!/bin/bash
# On the riscv host itself (no QEMU): do the host instruction sequences that
# QEMU's atomic helpers compile to order a later plain load?  (No Zacas on the
# C910, so the amocas modes are skipped.)
set -u
cd "$(dirname "$0")"
N=${N:-2000000}
grep -m1 -E '^(isa|uarch)' /proc/cpuinfo
for d in 16 64; do
	echo "--- native, max-delay=$d"
	for m in plain fence jit_lrsc lrsc_aqrl amoswap gcc_cas; do
		./sb_isolate $m "$N" 0 1 $d
	done
done
