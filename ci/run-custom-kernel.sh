#!/bin/bash
# Boot kernel/Image (our bpf-next build) in QEMU on the riscv runner and run
# the blitmus suite inside it.  KVM is unusable on the EM-RV1 runners (5.10
# vendor kernel, no H extension), so this is TCG; riscv-on-riscv TCG still
# issues guest loads/stores/fences as native riscv instructions, so the host's
# weak ordering is visible to the guest.
#
# Ubuntu 24.04's QEMU 8.2 has no Zacas (needed by the riscv JIT for BPF arena)
# and dies booting with -cpu max, so run everything in a Debian trixie
# container with a newer QEMU.
set -u
cd "$(dirname "$0")/.."

gunzip -kf kernel/Image.gz

# Optionally restrict the suite to the named binaries.
if [ -n "${TESTS:-}" ]; then
	mkdir -p bin.skipped
	for b in bin/*; do
		case " $TESTS " in *" $(basename "$b") "*) ;; *) mv "$b" bin.skipped/ ;; esac
	done
	ls bin
fi
bash ci/set-iterations.sh "${ITER:-400}"

exec docker run --rm --privileged -v "$PWD:/w" -w /w \
	-e CPUS="${CPUS:-4}" -e QEMU_CPU="${QEMU_CPU:-}" debian:trixie bash ci/boot-in-container.sh
