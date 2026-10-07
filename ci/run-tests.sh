#!/bin/bash
# Run the blitmus suite on the runner's own kernel, with whatever privilege
# route the runner offers: already root, sudo, or a privileged container.
set -u
cd "$(dirname "$0")/.."

bash ci/set-iterations.sh "${ITER:-4100}"

if [ "$(id -u)" = 0 ]; then
	echo ">>> running as root"
	exec ./run.sh
elif sudo -n true 2>/dev/null; then
	echo ">>> running via sudo"
	sudo apt-get update -qq && sudo apt-get install -y -qq libelf1t64 zlib1g >/dev/null
	exec sudo ./run.sh
elif docker info >/dev/null 2>&1; then
	echo ">>> running in a privileged ubuntu:24.04 container"
	exec docker run --rm --privileged -v "$PWD:/w" -w /w ubuntu:24.04 bash -c \
		'apt-get update -qq && apt-get install -y -qq libelf1t64 zlib1g >/dev/null && ./run.sh'
else
	echo ">>> no root, no sudo, no docker: cannot load BPF programs" >&2
	exit 1
fi
