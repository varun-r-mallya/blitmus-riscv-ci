# blitmus-riscv-ci

Runs [blitmus](https://github.com/puranjaymohan/blitmus) (BPF litmus tests) on
native riscv64 hardware via the free [RISE RISC-V runners](https://riscv-runners.riseproject.dev/)
(`ubuntu-24.04-riscv`, Scaleway EM-RV1 / T-Head TH1520).

- `bin/` — test binaries cross-built from blitmus `86ef823` (`make ARCH=riscv CC=riscv64-linux-gnu-gcc`), stripped.
- `litmus_tests/` — the litmus sources they were generated from.
- `ci/probe.sh` — dumps CPU/kernel/privilege/BPF/KVM info about the runner.
- `ci/run-tests.sh` — runs the suite as root, via sudo, or in a privileged container.

Trigger manually from the Actions tab (`workflow_dispatch`) to change iteration counts, or set `runner_kernel_label` (e.g. `ubuntu-26.04-riscv`) to also run on that pool's own kernel. The 26.04 early-access pool has not picked up our jobs so far.

## Custom kernel

The 24.04 runners run Scaleway's 5.10 vendor kernel (BPF JIT disabled, no BPF
atomics), which can't load these programs. The `custom-kernel` job boots
`kernel/Image.gz` (bpf-next, see `kernel/VERSION` and `kernel/config`) in QEMU
on the riscv board with virtme-ng, under KVM if `/dev/kvm` works, else TCG.
