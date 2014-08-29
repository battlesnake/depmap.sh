#!/usr/bin/bash

function fail {
	echo "Failed: $@" >&2
	exit 1
}

declare -a LINES
declare -A NODES

function buffer_lines {
	readarray -t LINES
}

function for_each_line {
	for LINE in "${LINES[@]}"
	do
		if [ "$LINE" ]
		then
			echo "$LINE"
		fi
	done
}

function index_nodes {
	while IFS='*' read NODE TARGETS
	do
		if [ -z "$NODE" ]
		then
			continue
		fi
		NODES["$NODE"]=${#NODES[@]}
	done < <(for_each_line)
}

function for_each_node {
	for NODE in "${!NODES[@]}"
	do
		echo "$NODE"
	done
}

function for_each_edge {
	while IFS='*' read -a LOCUS
	do
		NODE="${LOCUS[0]}"
		FROM="${NODES["$NODE"]}"
		for TARGET in "${LOCUS[@]:1}"
		do
			if [ -z "$TARGET" ]
			then
				continue
			fi
			TO="${NODES["$TARGET"]}"
			echo "$FROM" "$NODE" "$TO" "$TARGET"
		done
	done < <(for_each_line)
}

function plaintext_to_graphml {
	source ./graphml-head.xml
	
	while read NODE
	do
		FROM="${NODES["$NODE"]}"
		source ./graphml-node.xml
	done < <(for_each_node)

	while read FROM NODE TO TARGET
	do
		source ./graphml-edge.xml
	done < <(for_each_edge)
	
	source ./graphml-foot.xml
}

function plaintext_to_tgf {
	while read NODE
	do
		echo "${NODES["$NODE"]} $NODE"
	done < <(for_each_node)

	echo "#"

	while read FROM NODE TO TARGET
	do
		echo "$FROM $TO"
	done < <(for_each_edge)
}

function plaintext_to_dot {
	echo "digraph {"
	while read FROM NODE TO TARGET
	do
		echo "$NODE -> $TARGET"
	done < <(for_each_edge)
	echo "}"
}

function plaintext {
	./txt.awk -v ASSIGNMENT="$1" -v COMMA="$2"
}

function help {
	cat README
	exit
}

declare BASE
declare -a DIRS
declare FORMAT
declare SCOPE
declare -a SEARCH
while getopts :b:d:f:s:I:h OPT
do
	case "$OPT" in
		\?) fail "Invalid option: -$OPTARG";;
		:) fail "Option -$OPTARG requires a parameter";;
		h) help;;
		b) [ -z "$BASE" ] && BASE="$OPTARG" || fail "Base path already specified";;
		f) [ -z "$FORMAT" ] && FORMAT="$OPTARG" || fail "Format already specified";;
		s) [ -z "$SCOPE" ] && SCOPE="$OPTARG" || fail "Scope already specified";;
		I) [ -d "$OPTARG" ] && SEARCH+="$OPTARG" || fail "Cannot find directory '$OPTARG'";;
		*) ;&
		d) [ -e "$OPTARG" ] && DIRS+="$OPTARG" || fail "Cannot find '$OPTARG'";;
	esac
done

if [ ${#DIRS[@]} -eq 0 ]
then
	DIR+=( "$PWD" )
fi

for IDX in "${!DIRS[@]}"
do
	DIRS[$IDX]="$(realpath "${DIRS[$IDX]}")"
done

if [ -z "$BASE" ]
then
	BASE="${DIRS[0]}"
fi

BASE="$(realpath "$BASE")"

for IDX in "${!SEARCH[@]}"
do
	SEARCH[$IDX]="$(realpath "${SEARCH[$IDX]}")"
done

PT_DELIMS=( '*' '*' )

case "$FORMAT" in
tgf) OUT=plaintext_to_tgf;;
dot) OUT=plaintext_to_dot;;
graphml) OUT=plaintext_to_graphml;;
null) OUT=true;;
"") ;&
txt) OUT= PT_DELIMS=( '=' ',' );;
*) fail "Unknown output type: '$FORMAT'";;
esac

case "$SCOPE" in
"") ;&
local) RX='#include \"([^\"]+)(\")';;
global) RX='#include [\<\"]([^\>\"]+)([\>\"])';;
all) RX='#include [\<\"]([^\>\"]+)([\>\"])';;
*) fail "Unknown filter type: '$SCOPE'";;
esac

SWD=$(realpath $(dirname "$0"))

export BASE DIRS FORMAT SCOPE SEARCH RX

while read FILE
do
	FILEREL="$(realpath "$FILE" --relative-base="$BASE")"
	FILEFULL="$(realpath "$FILE")"
	NODENAME="${FILEREL%.*}"
	echo "$NODENAME"
	pushd "$(dirname "$FILE")" >/dev/null
	export FILEREL FILEFULL NODENAME
	$SWD/filter.pl "${SEARCH[@]}" < "$FILEFULL" | \
		sort | \
		uniq
	popd >/dev/null
done < <( find "${DIRS[@]}" -name '*.h' -or -name '*.tcc' -or -name '*.cpp' ) | \
	sort | \
	uniq | \
	plaintext "${PT_DELIMS[@]}" | \
	{
		if [ "$OUT" ]
		then
			buffer_lines
			index_nodes
			$OUT
		else
			cat
			echo ""
		fi
	}

exit 0
