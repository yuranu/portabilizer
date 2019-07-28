#!/bin/bash

# MIT License
#
# Copyright (c) 2019 Yuri Nudelman
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.
#
#
# https://github.com/yuranu/portabilizer

## Print usage and exit
## @param $1 exit code
function print_usage() {
	cat <<__USAGE__
Usage: $(basename $0) [OPTIONS]:
Pack all executable dependencies into a single portable executable archive.
[OPTIONS]:
    -b | --binary       Add ELF executable binary and all its dependencies to
                        the archive.
    -f | --file         Add an arbitrary file to the archive.
    -e | --entrypoint   Specify the entry point for the archive.
                        Default: executable first binary provided.
    -o | --output       Specify the name of the output executable archive.
                        Default: executable first binary provided + ".port".
    -h | --help         Show this message end exit.
__USAGE__

	if [ "$1" ]; then
		exit $1
	else
		exit 0
	fi
}

## Utility function - check if array contains an element
## @param $1 Array name
## @param $2 String to search
#3 @return 0 if element found, 1 otherwise
function array_contains() {
	local FOUND=1
	local ARR="$1[@]"
	for E in "${!ARR}"; do
		if [ "$E" == "$2" ]; then
			FOUND=0
			break
		fi
	done
	return $FOUND
}

## Utility function - print message to stderr and exit with code 1
## @param $* Message to print
function die() {
	echo >&2 "$*"
	exit 1
}

## Resolve dynamic lib depends of a binary.
## @param $1 Dynamic linker path.
## @param $2 ELF binary path.
function resolve_depends() {
	"$1" --list "$2" | grep -Po '(=>\s*)\K(.*)(?=\s\(0x[0-9a-fA-F]+\)$)'
}

## Resolve dynamic linker location from ELF.
## @param $1 ELF binary path.
function resolve_ld_linux() {
	readelf -l "$1" | grep -Po 'Requesting program interpreter: \K(.*)(?=\])'
}

## Generate a fake name to use for executable.
## The real name is reserved for a wrapper script.
## @param $1 ELF binary path
function gen_fake_exe_name() {
	echo "_____$(basename $1)"
}

## Rename and copy exe into working temp dir
## @param $1 ELF binary path
function prepare_fake_exe() {
	NAME="$TMPDIR/$(gen_fake_exe_name $1)"
	cp "$1" "$NAME"
	echo "$NAME"
}

## Create a tiny one-liner script that executes binary with specified
## dynamic linker, and LD_LIBRARY_PATH=.
## The script is created inside $TMPDIR.
## @param $1 ELF binary path
## @param $2 Dynamic linker path
function prepare_exe_wrapper() {
	WRAPPER_NAME="$TMPDIR/$(basename $1)"
	cat >"$WRAPPER_NAME" <<__SCRIPT__
#!/bin/bash
WRKDIR=\$(dirname \$0)
LD_LIBRARY_PATH="\$WRKDIR" \$WRKDIR/$(basename $2) \$WRKDIR/$(gen_fake_exe_name $1)
__SCRIPT__
	chmod 755 "$WRAPPER_NAME"
	echo "$WRAPPER_NAME"
}

## Add a file to list of files to collect
## @param $1 File path
function add_to_collect() {
	array_contains TOCOLLECT "$1" || TOCOLLECT+=("$1")
}

## Resolve binary dependencies, create launcher, and add all this + dynamic
## liker to the set of files to collect (array TOCOLLECT)
## @param $1 ELF binary path
function collect_binary() {
	# Get the dynamic linker.
	LD_LINUX=$(resolve_ld_linux "$1")
	if [ -z "LD_LINUX" ]; then
		die "Error retrieving dynamic linker location from ELF ($1)"
	fi

	# Get dynamic libs depends.
	DYN_LIBS=($(resolve_depends "$LD_LINUX" "$1"))
	if [ -z "DYN_LIBS" ]; then
		die "Error resolving ELF dependencies ($1)"
	fi

	add_to_collect "$LD_LINUX"
	for LIB in "${DYN_LIBS[@]}"; do
		add_to_collect "$LIB"
	done

	add_to_collect $(prepare_exe_wrapper "$1" "$LD_LINUX")
	add_to_collect $(prepare_fake_exe "$1")
}

## Launch cats into space.
## Not really, just output launcher script to stdout.
## @param $1 Entry point executable name.
function cat_launcher() {
	LAUNCHER_MARKER=$(awk '/^__LAUNCHER_SCRIPT__/ {print NR + 1; exit 0; }' $0)
	tail -n+$LAUNCHER_MARKER $0 | sed "s|__ENTRYPOINT__|$1|"
}

if [ "$#" -eq 0 ]; then
	print_usage
fi

TOCOLLECT=()
FILES_TOCOLLECT=()
BIN_TOCOLLECT=()

OUT_NAME=""

ENTRYPOINT=""

while [[ $# -gt 0 ]]; do
	key="$1"

	case $key in
	-b | --binary)
		array_contains BIN_TOCOLLECT "$2" && die "File specified twice ($2)"
		array_contains FILES_TOCOLLECT "$2" && die "File specified twice ($2)"
		BIN_TOCOLLECT+=("$(realpath $2)")
		if [ ! "$OUT_NAME" ]; then
			OUT_NAME="$2.port"
		fi
		if [ ! "$ENTRYPOINT" ]; then
			ENTRYPOINT=$(basename "$2")
		fi
		shift
		shift
		;;
	-f | --file)
		array_contains BIN_TOCOLLECT "$2" && die "File specified twice ($2)"
		array_contains FILES_TOCOLLECT "$2" && die "File specified twice ($2)"
		FILES_TOCOLLECT+=("$(realpath $2)")
		shift
		shift
		;;
	-o | --output)
		OUT_NAME="$2"
		shift
		shift
		;;
	-e | --entrypoint)
		ENTRYPOINT="$2"
		shift
		shift
		;;
	-h | --help)
		print_usage
		;;
	*) # unknown option
		die "Unknown option ($1)"
		;;
	esac
done

if [ ! "$ENTRYPOINT" ]; then
	die "Entrypoint not specified"
fi

ENTRYPOINT="$(basename $ENTRYPOINT)"

if [ ! "$OUT_NAME" ]; then
	die "Output file name not specified"
fi

# Prepare working directory.
TMPDIR=$(mktemp -d)
TMPTAR=$TMPDIR/payload.tar
trap "rm -rf $TMPDIR" EXIT

# Add payload files
for f in "${FILES_TOCOLLECT[@]}"; do
	TOCOLLECT+=("$f")
done

# Add binaries with dependencies
for b in "${BIN_TOCOLLECT[@]}"; do
	collect_binary "$b"
done

# Actually create a tar
echo "Generating executable archive with entry point [$ENTRYPOINT]"
for i in "${TOCOLLECT[@]}"; do
	tar -uvhf "$TMPTAR" -C "$(dirname $i)" "$(basename $i)" || die "Error creating tar"
done

# Final output
cat_launcher $ENTRYPOINT >"$OUT_NAME" || die "Error writing to $OUT_NAME"
cat $TMPTAR >>"$OUT_NAME" || die "Error writing to $OUT_NAME"
chmod 755 "$OUT_NAME"

echo "Executable archive created: $OUT_NAME"

# Done
exit 0

__LAUNCHER_SCRIPT__
#!/bin/bash

## launcher.sh
## Launcher script template to be embedded into the portabilizer executable
## archives.

# Prepare working dir.
WRKDIR=$(mktemp -d)
trap "rm -rf $WRKDIR" EXIT

# Find the data marker.
DATA_MARKER=$(awk '/^__DATA_MARKER__/ {print NR + 1; exit 0; }' $0)

# Extract data.
tail -n+$DATA_MARKER $0 | tar x -C $WRKDIR

# Launch the entry point (to be replaced with the actual entry point name).
$WRKDIR/__ENTRYPOINT__

# Exit with correct status
exit $?

# No trailing newlines, important.
__DATA_MARKER__
