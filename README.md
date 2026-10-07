# blitmus-riscv-ci

Runs [blitmus](https://github.com/puranjaymohan/blitmus) (BPF litmus tests) on
native riscv64 hardware via the free [RISE RISC-V runners](https://riscv-runners.riseproject.dev/)
(`ubuntu-24.04-riscv`, Scaleway EM-RV1 / T-Head TH1520).

- `bin/` — test binaries cross-built from blitmus `86ef823` (`make ARCH=riscv CC=riscv64-linux-gnu-gcc`), stripped.
- `litmus_tests/` — the litmus sources they were generated from.
- `ci/probe.sh` — dumps CPU/kernel/privilege/BPF/KVM info about the runner.
- `ci/run-tests.sh` — runs the suite as root, via sudo, or in a privileged container.

Trigger manually with a custom iteration count from the Actions tab (`workflow_dispatch`).
