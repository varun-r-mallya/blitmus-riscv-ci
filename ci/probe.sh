#!/bin/bash
# Dump everything relevant about the runner: CPU, kernel, privileges, BPF, KVM.
set +e

section() { echo; echo "===== $* ====="; }

section "uname";            uname -a
section "os-release";       cat /etc/os-release
section "cpuinfo";          cat /proc/cpuinfo
section "nproc / mem";      nproc; free -m
section "id / caps";        id; grep -E '^Cap(Inh|Prm|Eff|Bnd|Amb)' /proc/self/status
command -v capsh >/dev/null && capsh --decode="$(awk '/^CapEff/{print $2}' /proc/self/status)"
section "sudo";             sudo -n true && echo "sudo: yes" || echo "sudo: no"
section "container?";       cat /proc/1/cgroup; ls -la /.dockerenv 2>&1; cat /proc/1/sched 2>/dev/null | head -1
section "kvm";              ls -la /dev/kvm 2>&1
grep -o 'isa.*' /proc/cpuinfo | head -1 | grep -q '_h\b\|[^a-z]h[^a-z]' && echo "isa may include H" || echo "no H in isa string"
dmesg 2>/dev/null | grep -i kvm | head
section "bpf sysctls";      sysctl kernel.unprivileged_bpf_disabled net.core.bpf_jit_enable net.core.bpf_jit_harden 2>&1
section "kernel config";
for f in /proc/config.gz /boot/config-$(uname -r); do
	[ -e "$f" ] || continue
	echo "from $f"
	{ [[ $f == *.gz ]] && zcat "$f" || cat "$f"; } |
		grep -E 'CONFIG_(BPF|BPF_SYSCALL|BPF_JIT|BPF_JIT_ALWAYS_ON|DEBUG_INFO_BTF|KVM|RISCV_ISA_[A-Z_]+|NR_CPUS)='
	break
done
ls -la /sys/kernel/btf/vmlinux 2>&1
section "mounts";           mount | grep -E 'bpf|debugfs|tracefs|cgroup2' ; df -h /
section "docker";           docker info 2>&1 | head -30
section "lib deps";         ldd bin/sb_poonceonces
exit 0
