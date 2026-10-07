#!/bin/bash
# Inside debian:trixie on the riscv host: the same test as a guest under
# qemu-riscv64 (user mode, so no kernel and no BPF involved).
set -u
cd "$(dirname "$0")"
export DEBIAN_FRONTEND=noninteractive
N=${N:-2000000}

echo "::group::install"
echo 'deb http://deb.debian.org/debian-debug trixie-debug main' > /etc/apt/sources.list.d/debug.list
apt-get update -qq
apt-get install -y -qq qemu-user gdb binutils >/dev/null
apt-get install -y -qq qemu-user-dbgsym >/dev/null 2>&1 || echo "(no qemu-user-dbgsym)"
qemu-riscv64 --version | head -1
echo "::endgroup::"

echo "--- host code QEMU runs for amocas.d (helper_atomic_cmpxchgq_le) and amoswap.d (helper_atomic_xchgq_le)"
for h in helper_atomic_cmpxchgq_le helper_atomic_xchgq_le; do
	gdb -q -batch -ex "disassemble $h" "$(command -v qemu-riscv64)" 2>&1 |
		grep -E 'lr\.|sc\.|amo|fence|Dump|No symbol' | head -12
done

for d in 16 64; do
	echo "--- qemu-riscv64 -cpu rv64,zacas=true, max-delay=$d"
	for m in plain fence amocas amocas_fence jit_lrsc lrsc_aqrl amoswap gcc_cas; do
		qemu-riscv64 -cpu rv64,zacas=true ./sb_isolate $m "$N" 0 1 $d
	done
done
