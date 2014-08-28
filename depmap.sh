#!/bin/bash

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
	cat <<========================================
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<graphml
	xmlns="http://graphml.graphdrawing.org/xmlns"
	xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
	xmlns:y="http://www.yworks.com/xml/graphml"
	xmlns:yed="http://www.yworks.com/xml/yed/3"
	xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://www.yworks.com/xml/schema/graphml/1.1/ygraphml.xsd">
	<key for="node" id="d1" yfiles.type="nodegraphics"/>
	<graph id="depmap" edgedefault="directed">
========================================

	while read NODE
	do
		FROM="${NODES["$NODE"]}"
		cat <<========================================
		<node id="n_${FROM}">
			<data key="d1">
				<y:ShapeNode>
					<y:NodeLabel>$NODE</y:NodeLabel>
				</y:ShapeNode>
			</data>
		</node>
========================================
	done < <(for_each_node)

	while read FROM NODE TO TARGET
	do
		cat <<========================================
		<edge id="e_${FROM}_${TO}" source="n_${FROM}" target="n_${TO}"/>
========================================
	done < <(for_each_edge)

	cat <<========================================
	</graph>
</graphml>
========================================
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
	local ASSIGNMENT="$1" COMMA="$2"
	awk '
		BEGIN {
			ORS=""
			OFS=""
			key=""
			firstrow=1
			firstcol=0
		}
		{
			if ($1 != key) {
				key=$1
				if (!firstrow) {
					print "\n"
				}
				print $1 "'"$ASSIGNMENT"'"
				firstcol=1
				firstrow=0
			}
			for (i = 2; i <= NF; i++) {
				if ($i != key) {
					if (!firstcol) {
						print "'"$COMMA"'"
					} else {
						firstcol=0
					}
					print $i
				}
			}
		}'
}

function help {
	echo "./depmap.sh  [-b <base>]  [-d <directory>]  [-s local|global|all]  [-f graphml|tgf|dot|txt]  [-I <search-path>]"
	echo ""
	echo "  - Scan cpp/h/tcc files in <directory> tree(s) for #includes"
	echo "  - Apply filter"
	echo "  - Transform paths to be relative to <base> (for files within <base>)"
	echo "  - Dump data as graph using given output format"
	echo ""
	echo "  * <directory> defaults to the current directory if none are specified"
	echo "  * <base> defaults to the first <directory> if not specified"
	echo "  * <format> defaults to 'txt' if not specified"
	echo "  * <scope> defaults to 'local' if not specified"
	echo ""
	echo ""
	echo " Filters"
	echo "  - local is all \"#include\" with quoted filenames which are found"
	echo "  - global is \"#include\" and also <#include> which are found in search path"
	echo "  - all is all #include, even ones which cannot be found"
	echo ""
	echo " Formats"
	echo "  - graphml is GraphML (an xml-based format compatible with yEd)"
	echo "  - tgf is Trivial Graph Format (compatible with yEd but nodes are unlabelled)"
	echo "  - dot is DOT format (can be converted to GraphML via dottoxml but becomes undirected)"
	echo "  - txt is plain format file=dep1,...depN"
	echo ""
	echo " Requires recent versions of bash & realpath, awk, perl"
	echo ""
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

while read FILE
do
	FILEREL="$(realpath "$FILE" --relative-base="$BASE")"
	FILEFULL="$(realpath "$FILE")"
	NODENAME="${FILEREL%.*}"
	echo "$NODENAME"
	pushd "$(dirname "$FILE")" >/dev/null
	perl < "$FILEFULL" -ne '
		next unless /^'"$RX"'\s*$/;
		my $include = $1;
		my $global = $2 eq ">";
		my $sourcenodename = "'"$NODENAME"'";
		my $base = "'"$BASE"'";
		my @search = split(":", "'"$(IFS=":" echo "${SEARCH[@]}")"'");
		my $all = '"$([ "$3" == "all" ] && echo 1 || echo 0)"';
		my $found;
		if ($global) {
			use List::Util '\''first'\'';
			$loc = first { -e "$_/$include" } @search;
			$found = !!$loc;
		} else {
			$found = -e "$include";
			$loc = "./";
		}
		next unless $found || $all;
		my $nodename = `realpath "$loc"/"$include" --relative-base="$base"` if $found;
		$nodename =~ s/\.[^\.]*$// if $found;
		$nodename = "<$nodename>" if $global && !all;
		print "$sourcenodename\t$nodename\n";
		next;
		' | \
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
