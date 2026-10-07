#!/bin/bash
# Run the blitmus suite with whatever privilege route the runner offers:
#   1. already root, 2. sudo, 3. a privileged docker container.
set -u
cd "$(dirname "$0")/.."

ITER=${ITER:-4100}

# run.sh runs bin/* with defaults; honour ITER by wrapping each binary.
if [ "$ITER" != 4100 ]; then
	mkdir -p bin.real && mv bin/* bin.real/
	for b in bin.real/*; do
		printf '#!/bin/sh\nexec "%s" -i %s "$@"\n' "$PWD/$b" "$ITER" > "bin/$(basename "$b")"
		chmod +x "bin/$(basename "$b")"
	done
fi

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
