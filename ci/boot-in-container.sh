#!/bin/bash
# Runs as root inside debian:trixie (see run-custom-kernel.sh).
set -u
export DEBIAN_FRONTEND=noninteractive

echo "::group::install qemu + virtme-ng"
apt-get update -qq
apt-get install -y -qq qemu-system-misc libelf1t64 zlib1g python3-pip \
	busybox-static kmod iproute2 udev >/dev/null
BUILD_VIRTME_NG_INIT=0 pip3 install -q --break-system-packages virtme-ng
qemu-system-riscv64 --version | head -1
vng --version
echo "::endgroup::"

# The riscv JIT only enables BPF arena with Zacas (cmpxchg128).
if echo quit | qemu-system-riscv64 -M virt -cpu rv64,zacas=true -display none \
	-S -monitor stdio -serial none >/dev/null 2>&1; then
	CPU="rv64,zacas=true"
else
	CPU="rv64"
fi
echo ">>> booting $(cat kernel/VERSION) under TCG: -cpu $CPU, $CPUS vCPUs"

vng --verbose --force-9p --disable-kvm --run kernel/Image --root / \
	--rwdir /mnt=/w --cpus "$CPUS" --memory 8G "--qemu-opts=-cpu $CPU" \
	-- "uname -a; grep -m1 isa /proc/cpuinfo; cd /mnt && ./run.sh"
