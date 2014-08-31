#!/bin/bash

# This whole thing should just be one node.js script, but I'm working on Cygwin
# at the moment nodejs doesn't play well with it (but Windows doesn't support
# the rest of my environment, so running node externally would be a PITA as I
# like automating everything with scripts.

IFS=$' '

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

function graphml_default_presentation {
	local REQ="$1"
	shift
	case "$REQ" in
		keys)   echo "<key for=\"node\" id=\"nodelabel\" yfiles.type=\"nodegraphics\"/>";;
		branch) echo "<data key=\"nodelabel\"><y:ShapeNode><y:NodeLabel>${!#}</y:NodeLabel></y:ShapeNode></data>";;
		leaf)   echo "<data key=\"nodelabel\"><y:ShapeNode><y:NodeLabel>${!#}</y:NodeLabel></y:ShapeNode></data>";;
	esac
}

if [ "$1" == "depmap-gml" ]
then
	shift
	graphml_default_presentation "$@"
	exit
fi

function plaintext_to_graphml {
	declare GRAPHID=1
	declare -a ALLTOKENS
	declare -a PATHTOKENS
	declare -a PREVTOKENS=()
	declare NPATHTOKENS
	declare NPREVTOKENS=0
	declare IDX=0

	cat \
<<========================================
<?xml version="1.0" encoding="UTF-8" standalone="no"?>
<graphml
xmlns="http://graphml.graphdrawing.org/xmlns"
xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance"
xmlns:y="http://www.yworks.com/xml/graphml"
xmlns:yed="http://www.yworks.com/xml/yed/3"
xsi:schemaLocation="http://graphml.graphdrawing.org/xmlns http://www.yworks.com/xml/schema/graphml/1.1/ygraphml.xsd">
========================================

	"$GMLPRES" depmap-gml keys

	echo "<graph id=\"g_0\" edgedefault=\"directed\">"

	while read NODE
	do

		FROM="${NODES["$NODE"]}"
		IFS='/' read -a ALLTOKENS <<<"$NODE"
		NALLTOKENS=${#ALLTOKENS[@]}
		NPATHTOKENS=$((NALLTOKENS - 1 < LEVELS ? NALLTOKENS - 1 : LEVELS))
		NPATHTOKENS=$((NPATHTOKENS < 0 ? 0 : NPATHTOKENS))
		PATHTOKENS=("${ALLTOKENS[@]::$NPATHTOKENS}")

		for ((IDX = NPREVTOKENS - 1; IDX >= 0; IDX--))
		do
			if (( IDX < NPATHTOKENS )) && [ "${PATHTOKENS[$IDX]}" == "${PREVTOKENS[$IDX]}" ]
			then
				break
			fi
			echo "</graph></node>"
		done

		for ((IDX = IDX + 1; IDX < NPATHTOKENS; IDX++))
		do
			echo "<node id=\"n_g_${GRAPHID}\">"
			"$GMLPRES" depmap-gml branch "${PATHTOKENS[@]::$((IDX+1))}"
			echo "<graph id=\"g_${GRAPHID}\">"
			((GRAPHID++))
		done

		PREVTOKENS=("${PATHTOKENS[@]}")
		NPREVTOKENS=$NPATHTOKENS

		echo "<node id=\"n_${FROM}\">"
		"$GMLPRES" depmap-gml leaf "${PATHTOKENS[@]}" "${ALLTOKENS[*]:$NPATHTOKENS}"
		echo "</node>"

	done < <(for_each_node | sort -k1 -t'*')

	for IDX in $(seq -s ' ' $((NPREVTOKENS-1)) -1 0)
	do
		echo "</graph></node>"
	done

	while IFS=$' ' read FROM NODE TO TARGET
	do
		echo "<edge id=\"e_${FROM}_${TO}\" source=\"n_${FROM}\" target=\"n_${TO}\"/>"
	done < <(for_each_edge)

	echo "</graph></graphml>"
}

function plaintext_to_tgf {
	while read NODE
	do
		echo "${NODES["$NODE"]} $NODE"
	done < <(for_each_node)

	echo "#"

	while IFS=$' ' read FROM NODE TO TARGET
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
	echo "./depmap.sh"
	echo "  [-d directory]"
	echo "  [-b base]"
	echo "  [-f exts]"
	echo "  [-s local|global|all]"
	echo "  [-o graphml|tgf|dot|txt]"
	echo "  [-I search-path]"
	echo "  [-g levels]"
	echo "  [-p presentation]"
	echo ""
	echo " Mark K Cowan, mark@battlesnake.co.uk, github.com/battlesnake"
	echo ""
	echo "  - Scan files in <directory> tree(s) (which match extension <filter>)"
	echo "    for #includes"
	echo "  - Restrict to includes within given <scope>"
	echo "  - Transform paths to be relative to <base> (for files within <base>)"
	echo "  - Graphml only: group <levels> subdirectory levels as subgraphs"
	echo "  - Graphml only: use <presentation> file to add visual formatting to"
	echo "    nodes"
	echo "  - Dump data as graph using given <output> format"
	echo ""
	echo "  * <directory> defaults to the current directory if none are specified"
	echo "  * <base> defaults to the first <directory> if not specified"
	echo "  * <exts> defaults to c,cpp,h,hpp,tcc"
	echo "  * <format> defaults to 'txt' if not specified"
	echo "  * <scope> defaults to 'local' if not specified"
	echo "  * <levels> defaults to 0"
	echo "  * <presentation>, if unspecified defaults to just adding node labels"
	echo ""
	echo " Filters (-f)"
	echo "  * comma-separated list of file extensions to scan for,"
	echo "    e.g. c,cpp,h,hpp,tcc"
	echo "  * you may get a more meaningful graph by restricting to only"
	echo "    headers: h,hpp"
	echo ""
	echo " Scope (-s)"
	echo "  - local is all \"#include\" with quoted filenames which are found"
	echo "  - global is \"#include\" and also <#include> which are found in"
	echo "    search path"
	echo "  - all is all #include, even ones which cannot be found"
	echo ""
	echo " Output formats (-o)"
	echo "  - graphml is GraphML (an xml-based format compatible with yEd)"
	echo "  - tgf is Trivial Graph Format (compatible with yEd but nodes are"
	echo "    unlabelled)"
	echo "  - dot is DOT format (can be converted to GraphML via dottoxml but"
	echo "    becomes undirected)"
	echo "  - txt is plain format file=dep1,...depN"
	echo ""
	echo " Presentation (-p, graphml only)"
	echo "  - A script which is called for each graph, node, and edge."
	echo "    Syntax: ./myscript depmap-gml [keys|branch|leaf] <path>"
	echo "            keys   = create <key> tags for start of document"
	echo "            branch = create <data> tags for subgraph node"
	echo "            leaf   = create <data> tags for leaf node"
	echo "    Output: STDOUT: xml fragments with presentational information to"
	echo "            be embedded in the relevant xml node"
	echo "    Example invocation:"
	echo "                    ./myscript depmap-gml leaf service auth/facebook"
	echo "    Example output: "
	echo '                    echo "<data key="nodelabel"><y:ShapeNode>"'
	echo '                    echo "  <y:NodeLabel>${!#}</y:NodeLabel>"'
	echo '                    echo "</y:ShapeNode></data>"'
	echo "  - The presenter script is first searched for in the 'presenters'"
	echo "    directory which is in the same folder as the depmap.sh script."
	echo "  - If not found there, then it is assumed to be the path to a script."
	echo "  - An example presenter called 'modern' is provided."
	echo "    Use '-p modern' in the command line to invoke the script at"
	echo "    presenters/modern.sh"
	echo ""
	echo " Requires recent versions of bash & realpath, awk, perl"
	echo ""
	exit
}

declare DEBUG=
declare BASE
declare -a DIRS
declare -a FILTERS
declare FORMAT
declare SCOPE
declare -a SEARCH
declare LEVELS
declare GMLPRES
while getopts :b:d:f:o:s:I:g:p:h@ OPT
do
	case "$OPT" in
		\?) fail "Invalid option: -$OPTARG";;
		:) fail "Option -$OPTARG requires a parameter";;
		@) DEBUG=yes;;
		h) help;;
		b) [ -z "$BASE" ] && BASE="$OPTARG" || fail "Base path already specified";;
		f) IFS=':' FILTERS+=("$OPTARG");;
		o) [ -z "$FORMAT" ] && FORMAT="$OPTARG" || fail "Format already specified";;
		s) [ -z "$SCOPE" ] && SCOPE="$OPTARG" || fail "Scope already specified";;
		I) [ -d "$OPTARG" ] && SEARCH+="$OPTARG" || fail "Cannot find directory '$OPTARG'";;
		g) [ -z "$LEVELS" ] && LEVELS="$OPTARG" || fail "Grouping levels already specified";;
		p) [ -z "$GMLPRES" ] && GMLPRES="$OPTARG" || fail "Presentation script already specified";;
		*) ;&
		d) [ -e "$OPTARG" ] && DIRS+=("$OPTARG") || fail "Cannot find '$OPTARG'";;
	esac
done

if [ ${#DIRS[@]} -eq 0 ]
then
	DIRS=("$PWD")
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

if [ ${#FILTERS[@]} -eq 0 ]
then
	FILTERS=( h hpp c cpp tcc )
fi

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

if [ "$FORMAT" != "graphml" ] && ([ "$GMLPRES" ] || [ "$LAYERS" ])
then
	fail "-p/-g only valid for graphml output format"
elif [ -z "$GMLPRES" ]
then
	GMLPRES="$0"
fi

if [ "$FORMAT" == "graphml" ]
then
	GMLPRESTEST="$(dirname $(realpath "$0"))/presenters/${GMLPRES}.sh"
	if [[ "$GMLPRES" =~ ^[a-z]+$ ]] && [ -e "$GMLPRESTEST" ]
	then
		GMLPRES="$GMLPRESTEST"
	else
		GMLPRES="$(realpath "$GMLPRES")"
		if [ ! -e "$GMLPRES" ]
		then
			fail "Cannot find presenter '$GMLPRES'"
		fi
	fi
fi

case "$SCOPE" in
"") ;&
local) RX='#include \"([^\"]+)(\")';;
global) RX='#include [\<\"]([^\>\"]+)([\>\"])';;
all) RX='#include [\<\"]([^\>\"]+)([\>\"])';;
*) fail "Unknown filter type: '$SCOPE'";;
esac

PREDICATES=()
for FILTER in "${FILTERS[@]}"
do
	if [ ${#PREDICATES[@]} -ne 0 ]
	then
		PREDICATES+=(-or)
	fi
	PREDICATES+=(-name "*.$FILTER")
done

if [ "$DEBUG" == "yes" ]
then
	function showvar {
		echo -ne "$1\t"
		shift
		printf -- "[%s] " "$@"
		echo ""
	}
	{
		showvar "Base" "$BASE"
		showvar "Directories" "${DIRS[@]}"
		showvar "Filters" "${FILTERS[@]}"
		showvar "Scope" "$SCOPE"
		showvar "Search path" "${SEARCH[@]}"
	} | column -t -s $'\t'
	echo ""
	{
		showvar "Output" "$OUT"
		showvar "Predicates" "${PREDICATES[@]}"
	} | column -t -s $'\t'
fi >&2

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
		my $all = '"$([ "$SCOPE" == "all" ] && echo 1 || echo 0)"';
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
done < <(
		if [ -z "$DEBUG" ] || [ ! -e "/tmp/depmap.pt" ]
		then
			find "${DIRS[@]}" "${PREDICATES[@]}"
		fi
	) | \
	sort | \
	uniq | \
	plaintext "${PT_DELIMS[@]}" | \
	{
		if [ "$DEBUG" ]
		then
			if [ -e "/tmp/depmap.pt" ]
			then
				cat > /dev/null
				echo >&2 "DEBUG: Re-using parsed data from last depmap command"
				echo >&2 "Delete /tmp/depmap.pt or run without DEBUG flag to re-parse new options/files"
				cat /tmp/depmap.pt
			else
				tee /tmp/depmap.pt
			fi
		else
			cat
		fi
	} | \
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
