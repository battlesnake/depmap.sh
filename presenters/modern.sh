#!/bin/bash

COLORS=(000000 FFFFFF

	FF9999 FFCC99 FFFF99 CCFF99
	99FF99 99FFCC 99FFFF 99CCFF
	9999FF CC99FF FF99FF

	FFCCCC FFFFCC CCFFCC \
	CCFFFF CCCCFF FFCCFF
)

SHAPES=(rectangle roundrectangle ellipse hexagon diamond octagon)

declare -A STYLES=(
	[default]="0 17"
	[main]="3 3"
	[model]="1 16"
	[controller]="2 4"
	[view]="4 10"
	[service]="5 15"
)

if [ "$1" != "depmap-gml" ]
then
	echo >&2 "This script is a presentation script for use with depmap.sh"
	exit 1
fi
shift

REQ="$1"
shift

case "$REQ" in
	keys)   echo '<key for="node" id="graphics" yfiles.type="nodegraphics"/>';;
	branch)
	exit
	TEXTCOLOR=000000
	BORDERCOLOR=000000
	BORDERWIDTH=1.0
	SHAPE=roundrectangle
	FILLCOLOR=FFFFFF
	cat <<EOF
<data key="graphics"><y:ProxyAutoBoundsNode><y:Realizers active="0"><y:GroupNode>
<y:NodeLabel textColor="#${TEXTCOLOR}">${!#}</y:NodeLabel>
<y:Shape type="${SHAPE}"/>
</y:GroupNode><y:GroupNode>
<y:Fill color="#${FILLCOLOR}" transparent="false"/>
<y:BorderStyle color="#${BORDERCOLOR}" type="line" width="${BORDERWIDTH}"/>
<y:Shape type="${SHAPE}"/>
</y:GroupNode></y:Realizers></y:ProxyAutoBoundsNode></data>
EOF
;;
	leaf)
	TEXTCOLOR=000000
	BORDERCOLOR=000000
	BORDERWIDTH=1.0
	STYLE=
	# Exact matches
	for ((IDX=$#; IDX > 0; IDX--))
	do
		STYLE="${STYLES["${!IDX}"]}"
		if [ "$STYLE" ]
		then
			break
		fi
	done
	# Partial matches, synonyms
	for ((IDX=$#; IDX > 0; IDX--))
	do
		if [[ "${!IDX}" =~ model|request|element|node ]]
		then
			STYLE="${STYLES["model"]}"
		elif [[ "${!IDX}" =~ controller|compiler ]]
		then
			STYLE="${STYLES["controller"]}"
		elif [[ "${!IDX}" =~ service|server|manager|converter|codec|parser ]]
		then
			STYLE="${STYLES["service"]}"
		elif [[ "${!IDX}" =~ view|interface|page|report|layout|format ]]
		then
			STYLE="${STYLES["view"]}"
		fi
		if [ "$STYLE" ]
		then
			break
		fi
	done
	# Default style
	if [ -z "$STYLE" ]
	then
		STYLE="${STYLES["default"]}"
	fi
	read SHAPE_IDX COLOR_IDX <<<"$STYLE"
	SHAPE="${SHAPES[$SHAPE_IDX]}"
	FILLCOLOR="${COLORS[$COLOR_IDX]}"
	cat <<EOF
<data key="graphics"><y:ShapeNode>
<y:NodeLabel textColor="#${TEXTCOLOR}">${!#}</y:NodeLabel>
<y:Fill color="#${FILLCOLOR}" transparent="false"/>
<y:BorderStyle color="#${BORDERCOLOR}" type="line" width="${BORDERWIDTH}"/>
<y:Shape type="${SHAPE}"/>
</y:ShapeNode></data>
EOF
;;
esac
