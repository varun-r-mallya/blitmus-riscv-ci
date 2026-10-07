#!/bin/bash
# Boot kernel/Image (our bpf-next build) in QEMU on the riscv runner and run
# the blitmus suite inside it.  Uses KVM if /dev/kvm really works, else TCG
# (riscv-on-riscv TCG still issues guest loads/stores/fences as native riscv
# instructions, so the host's weak ordering is visible to the guest).
set -u
cd "$(dirname "$0")/.."

ITER=${ITER:-400}
CPUS=${CPUS:-4}

echo "::group::install qemu + virtme-ng"
sudo apt-get update -qq
sudo apt-get install -y -qq qemu-system-misc libelf1t64 zlib1g python3-pip busybox-static >/dev/null
sudo env BUILD_VIRTME_NG_INIT=0 pip3 install -q --break-system-packages virtme-ng
vng --version
echo "::endgroup::"

gunzip -kf kernel/Image.gz

echo "::group::KVM probe"
ls -la /dev/kvm
sudo dmesg 2>/dev/null | grep -i kvm | tail
# Boot to the (expected) root-mount panic; if the kernel prints its banner
# under -accel kvm, KVM works.
sudo timeout 60 qemu-system-riscv64 -M virt -accel kvm -cpu host -m 512 -smp 1 \
	-nographic -no-reboot -kernel kernel/Image \
	-append "console=ttyS0 panic=-1" > kvm-probe.txt 2>&1
KVM=0
grep -q "Linux version" kvm-probe.txt && KVM=1
tail -5 kvm-probe.txt
echo "KVM usable: $KVM"
echo "::endgroup::"

bash ci/set-iterations.sh "$ITER"

if [ "$KVM" = 1 ]; then
	accel=()
	echo ">>> booting custom kernel under KVM, $CPUS vCPUs"
else
	# -cpu max enables Zacas, which the riscv JIT needs for BPF arena.
	accel=(--disable-kvm --qemu-opts "-cpu max")
	echo ">>> KVM unavailable: booting custom kernel under TCG, $CPUS vCPUs"
fi

sudo vng --verbose --force-9p --run kernel/Image --root / \
	--rwdir /mnt="$PWD" --cpus "$CPUS" --memory 8G "${accel[@]}" \
	-- "uname -a; grep -m1 isa /proc/cpuinfo; cd /mnt && ./run.sh"
