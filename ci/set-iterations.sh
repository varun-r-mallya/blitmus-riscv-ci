#!/bin/bash
# run.sh runs every bin/* with no arguments; to honour a custom iteration
# count, move the real binaries to bin.real/ and leave relative-path wrappers
# in bin/ (relative so they also work when the tree is mounted in a guest).
set -eu
cd "$(dirname "$0")/.."

ITER=${1:-4100}
[ "$ITER" = 4100 ] && exit 0
[ -d bin.real ] && exit 0

mkdir bin.real && mv bin/* bin.real/
for b in bin.real/*; do
	n=$(basename "$b")
	printf '#!/bin/sh\nexec "$(dirname "$0")/../bin.real/%s" -i %s "$@"\n' "$n" "$ITER" > "bin/$n"
	chmod +x "bin/$n"
done
