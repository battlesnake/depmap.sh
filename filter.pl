#!/usr/bin/perl
while (<>) {
	my $rx = qr/$ENV{'RX'}/;
	next unless my ($include, $quot) = $_ =~ $rx;
	my $global = $quot eq ">";
	my $sourcenodename = $ENV{'NODENAME'};
	my $base = $ENV{'BASE'};
	my @search = @ARGV;
	my $all = $ENV{'SCOPE'} == 'all';
	my $found;
	if ($global) {
		use List::Util 'first';
		$loc = first { -e "$_/$include" } @search;
		$found = !!$loc;
		$nodename = $include;
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
}
