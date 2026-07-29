#!/bin/sh
# SVN invokes --diff-cmd programs as: -u -L label1 -L label2 file1 file2.
# Adapt that fixed protocol to a two-file diff viewer.
set -eu

if [ "$#" -ne 7 ] || [ "$1" != "-u" ] || [ "$2" != "-L" ] || [ "$4" != "-L" ]; then
	printf '%s\n' 'usage: svn-difft-wrapper.sh -u -L label1 -L label2 file1 file2' >&2
	exit 2
fi

old_file=$6
new_file=$7
exec difft -- "$old_file" "$new_file"
