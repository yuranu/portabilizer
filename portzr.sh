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

## Print usage and exit
function print_usage {
cat << END_USAGE
Usage: $0 exe [output]
Pack all executable dependencies into a single portable executable archive.
    exe          Path to the input executable.
    output       Name of the output executable archive. Default: [exe].port
END_USAGE
exit 0
}

## Resolve dynamic lib depends of a binary.
## @param $1 Dynamic linker path.
## @param $2 ELF binary path.
function resolve_depends {
	$1 --list $2 | grep -Po '(=>\s*)\K(.*)(?=\s\(0x[0-9a-fA-F]+\)$)'
}

## Resolve dynamic linker location from ELF.
## @param $1 ELF binary path.
function resolve_ld_linux {
	readelf -l $1 | grep -Po 'Requesting program interpreter: \K(.*)(?=\])'
}

## Launch cats into space.
## Not really, just output launcher script to stdout.
## @param $1 Entry point executable name.
function cat_launcher {
	LAUNCHER_MARKER=`awk '/^__LAUNCHER_SCRIPT__/ {print NR + 1; exit 0; }' $0`
	tail -n+$LAUNCHER_MARKER $0 | sed "s|__ENTRYPOINT__|$1|"
}

function die {
	echo "$*" 1>&2 ; exit 1;
}

if [ "$#" -ne 2 ] && [ "$#" -ne 1 ] ; then
	print_usage
fi

if [ "$#" -eq 1 ] ; then
	OUT_NAME="$1.port"
else
	OUT_NAME="$2"
fi

# Prepare working directory.
TMPDIR=$(mktemp -d)
TMPTAR=$TMPDIR/payload.tar
trap "rm -rf $TMPDIR" EXIT

# Get the dynamic linker.
LD_LINUX=$(resolve_ld_linux $1)
if [ -z "LD_LINUX" ] ; then
	die "Error retrieving dynamic linker location from ELF ($1)"
fi

# Get dynamic libs depends.
DYN_LIBS=($(resolve_depends $LD_LINUX $1))
if [ -z "DYN_LIBS" ] ; then
	die "Error resolving ELF dependencies ($1)"
fi

# Add the dyhnamic linker to the tar.
tar -chf $TMPTAR -C $(dirname $LD_LINUX) \
	--transform="s|$(basename $LD_LINUX)|ld-linux.so|" \
	$(basename $LD_LINUX) || die "Error creating tar"

# Now add all the dependencies.
for i in "${DYN_LIBS[@]}" ; do
	tar -uhf $TMPTAR -C $(dirname $i) $(basename $i) || die "Error creating tar"
done

# Add the actual executable.
tar -uhf $TMPTAR -C $(dirname $1) $(basename $1) || die "Error creating tar"

# Final output
cat_launcher $(basename $1) > "$OUT_NAME" || die "Error writing to $2"
cat $TMPTAR >> "$OUT_NAME" || die "Error writing to $2"
chmod 755 $2

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
DATA_MARKER=`awk '/^__DATA_MARKER__/ {print NR + 1; exit 0; }' $0`


# Extract data.
tail -n+$DATA_MARKER $0 | tar x -C $WRKDIR

# Launch the entry point (to be replaced with the actual entry point name).
LD_LIBRARY_PATH=$WRKDIR:$LD_LIBRARY_PATH $WRKDIR/ld-linux.so $WRKDIR/__ENTRYPOINT__

# Exit with correct status
exit $?

# No trailing newlines, important.
__DATA_MARKER__
