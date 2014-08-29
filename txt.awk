#!/usr/bin/awk -f
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
		print $1 ASSIGNMENT
		firstcol=1
		firstrow=0
	}
	for (i = 2; i <= NF; i++) {
		if ($i != key) {
			if (!firstcol) {
				print COMMA
			} else {
				firstcol=0
			}
			print $i
		}
	}
}
