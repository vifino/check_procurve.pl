#!/usr/bin/perl -w

# Authors: Martin Bärtl, Adrian "vifino" Pistol
# written: 14.11.07
# updated: 05.02.16
#
# Nagios plugin to get fan and power supply state of HP ProCurve switches
#
# LICENSE
#	Licensed under the GPL w/ absolutely no warranty of any kind.
# VERSIONS
# 0.2
#	Modified by vifino.
#	- -P 2 shows only second fan, use -P 3 to show both.
#	- Switched Fan OID's, they were flipped for my switch, at least. (HP ProCurve 3400cl) 
#	- 
# 0.1
#	First Release
# 0.1.1
#	- Added license information, Author, etc.
#	- corrected some spelling
#
# CONTACT
#	mailto: martin AT baertl.net
#

use strict;
use Getopt::Long;
Getopt::Long::Configure ('no_ignore_case');
use Net::SNMP;

my $version = "0.1.1";

my $verbose;
my $timeout = 2; 
my $hostname = "";
my $community = "public";
my $help;
my $ver;
my $Fan = 0;
my $Power = 0;
my $retval = 3;
my $retmessage = "";
my $Fanstate;
my $Powerstate;
my $Powerstate2;

my %ERRORS = (	'OK'		=>	'0',
				'WARNING'	=>	'1',
				'CRITICAL'	=>	'2',
				'UNKNOWN'	=>	'3'
				);

my $result = GetOptions (	"v" => \$verbose,
							"C=s" => \$community,
							"help"  => \$help,
							"H=s" => \$hostname,
							"t=i" => \$timeout,
							"V" => \$ver,
							"F" => \$Fan,
							"P=i" => \$Power
							);

my $FanOID = ".1.3.6.1.4.1.11.2.14.11.1.2.6.1.4.1"; # HP ProCurve Fan sensor
my $PowerOID = ".1.3.6.1.4.1.11.2.14.11.1.2.6.1.4.2"; # HP ProCurve PowerSupply sensor
my $PowerOID2 = ".1.3.6.1.4.1.11.2.14.11.1.2.6.1.4.3"; # HP ProCurve 2nd PowerSupply sensor

if ( $verbose ) {
	print "Variables set:\n";
	print "Hostname:\t" . $hostname . "\n";
	print "Community:\t" . $community . "\n";
	print "timeout:\t" . $timeout . " seconds\n";
	print "Fan check:\t" . $Fan . "\n";
	print "Power check:\t" . $Power . "\n";
	print "verbose output:\t" . $verbose . "\n";
}
if ( $ver ) {
	print "$0 Version: " . $version . "\n";
	exit($ERRORS{'OK'});
}
if ( $help ) {
	print "Usage:\n";
	print "$0 -H hostname -F|P Number [-t timeout (seconds)] [-C community] [-V] [-v verbosity level] [-h]\n";
	print "-V\tdisplay Version.\n";
	print "-h\tprint this help.\n";
	print "-v\tenables verbose output.\n";
	print "-C\tdefine SNMP community, defaults to public.\n";
	print "-H\tdefine hostname or IP-Adress to check.\n";
	print "-t\ttimeout in seconds to wait for SNMP response.\n";
	print "-F\tcheck fan state. Either -F or -P or both have to be supplied.\n";
	print "-P\tNumber of power supplies to check (1 or 2 are valid arguments). Either -F or -P or both have to be supplied.\n";
	exit($ERRORS{'OK'});
}
if ( ( ! $hostname ) || ( ( ! $Fan ) && ( ! $Power ) ) ) {
	print "Usage: $0 -H hostname -F -P Number [-t timeout (ms)] [-C community] [-V] [-v verbosity level] [-h]\n";
	exit($ERRORS{'WARNING'});
}

my ($session, $error) = Net::SNMP -> session(	-hostname	=>	$hostname,
												-version	=>	'snmpv2c',
												-community	=>	$community,
												-timeout	=>	$timeout,
											);

if ( !defined($session) ) {
	printf( "ERROR: %s.\n", $error ) if $verbose;
	print "SNMP session error.";
	exit($ERRORS{'UNKNOWN'});
}

if ( $Fan ) {
	my ($SNMPresultFan, $SNMPerrorFan) = $session -> get_request( -varbindlist => [$FanOID] );
	if ( !defined($SNMPresultFan) ) {
		printf( "ERROR: %s.\n", $SNMPerrorFan ) if $verbose;
		$session -> close;
		print "SNMP result error.  Maybe not a HP ProCurve switch?";
		exit($ERRORS{'UNKNOWN'});
	}
	$Fanstate = $SNMPresultFan -> {$FanOID};
	print "Status: " . $Fanstate . "\n" if $verbose;
	if ( $Fanstate !~ /[12345]/ ) {
		print "Invalid SNMP Response: $Fanstate. Maybe not a HP ProCurve switch or fan sensor not installed?";
		exit($ERRORS{'WARNING'});
	}
	if ( $Fanstate == 4 ) {
		$retval = $ERRORS{'OK'};
		$retmessage .= "Fans OK. ";
	}
	elsif ( $Fanstate == 3 ){
		$retval = $ERRORS{'WARNING'};
		$retmessage .= "Fans are in WARNING state. ";
	}
	elsif ( $Fanstate == 2 ) {
		$retval = $ERRORS{'CRITICAL'};
		$retmessage .= "Fans are CRITICAL. ";
	}
	elsif ( $Fanstate == 5 ) {
		$retval = $ERRORS{'WARNING'};
		$retmessage .= "No fan present. ";
	}
	else {
		$retval = $ERRORS{'UNKNOWN'};
		$retmessage .= "Fan state UNKNOWN. ";
	}
}
if ( $Power && $Power != 2 ) {
	my ($SNMPresultPower, $SNMPerrorPower) = $session -> get_request( -varbindlist => [$PowerOID] );
	if ( !defined($SNMPresultPower) ) {
		printf( "ERROR: %s.\n", $SNMPerrorPower ) if $verbose;
		$session -> close;
		print "SNMP result error.  Maybe not a HP ProCurve switch?";
		exit($ERRORS{'UNKNOWN'});
	}
	$Powerstate = $SNMPresultPower -> {$PowerOID};
	print "Status: " . $Powerstate . "\n" if $verbose;
	if ( $Powerstate !~ /[12345]/ ) {
		print "Invalid SNMP Response: $Powerstate. Maybe not a HP ProCurve switch or power supply sensor not installed?";
		exit($ERRORS{'WARNING'});
	}
	if ( $Powerstate == 4 ) {
		$retmessage .= "Primary Power Supply OK. ";
		if ( !( $retval == $ERRORS{'WARNING'} || $retval == $ERRORS{'CRITICAL'} || ( $retval == $ERRORS{'UNKNOWN'} && $Fan ) ) ) {
			$retval = $ERRORS{'OK'};
		}
	}
	elsif ( $Powerstate == 3 ) {
		$retmessage .= "Primary Power Supply is in WARNING state. ";
		if ( ! ( $retval == $ERRORS{'CRITICAL'} ) ) {
			$retval = $ERRORS{'WARNING'};
		}
	}
	elsif ( $Powerstate == 2 ) {
		$retmessage .= "Primary Power Supply is CRITICAL. ";
		$retval = $ERRORS{'CRITICAL'};
	}
	elsif ( $Powerstate == 5 ) {
		$retmessage .= "Primary Power Supply not present. ";
		if ( ! ( $retval == $ERRORS{'CRITICAL'} ) ) {
			$retval = $ERRORS{'WARNING'};
		}
	}
	else {
		$retmessage .= "Primary Power Supply state UNKNOWN. ";
		if ( $retval == $ERRORS{'OK'} ) {
			$retval = $ERRORS{'UNKNOWN'};
		}
	}
}
if ( $Power == 2 || $Power == 3 ) {
	if ( $Power == 2 ) {
		my ($SNMPresultPower, $SNMPerrorPower) = $session -> get_request( -varbindlist => [$PowerOID] );
		if ( !defined($SNMPresultPower) ) {
			printf( "ERROR: %s.\n", $SNMPerrorPower ) if $verbose;
			$session -> close;
			print "SNMP result error.  Maybe not a HP ProCurve switch?";
			exit($ERRORS{'UNKNOWN'});
		}
		$Powerstate = $SNMPresultPower -> {$PowerOID};
	}
	my ($SNMPresultPower2, $SNMPerrorPower2) = $session -> get_request( -varbindlist => [$PowerOID2] );
	if ( !defined($SNMPresultPower2) ) {
		printf( "ERROR: %s.\n", $SNMPerrorPower2 ) if $verbose;
		$session -> close;
		print "SNMP result error. Maybe not a HP ProCurve switch?";
		exit($ERRORS{'UNKNOWN'});
	}
	$Powerstate2 = $SNMPresultPower2 -> {$PowerOID2};
	print "Status: " . $Powerstate2 . "\n" if $verbose;
	if ( $Powerstate2 !~ /[12345]/ ) {
		print "Invalid SNMP Response: $Powerstate2. Maybe not a HP ProCurve switch or second power supply sensor not installed?";
		exit($ERRORS{'WARNING'});
	}
	if ( $Powerstate2 == 4 ) {
		$retmessage .= "Secondary Power Supply OK. ";
		if ( !( $retval == $ERRORS{'WARNING'} || $retval == $ERRORS{'CRITICAL'} || ( $retval == $ERRORS{'UNKNOWN'} && ( $Fan || $Powerstate == 1 ) ) ) ) {
			$retval = $ERRORS{'OK'};
		}
	}
	elsif ( $Powerstate2 == 3 ) {
		$retmessage .= "Secondary Power Supply is in WARNING state. ";
		if ( ! ( $retval == $ERRORS{'CRITICAL'} ) ) {
			$retval = $ERRORS{'WARNING'};
		}
	}
	elsif ( $Powerstate2 == 2 ) {
		$retmessage .= "Secondary Power Supply is CRITICAL. ";
		$retval = $ERRORS{'CRITICAL'};
	}
	elsif ( $Powerstate2 == 5 ) {
		$retmessage .= "Secondary Power Supply not present. ";
		if ( ! ( $retval == $ERRORS{'CRITICAL'} ) ) {
			$retval = $ERRORS{'WARNING'};
		}
	}
	else {
		$retmessage .= "Secondary Power Supply state UNKNOWN. ";
		if ( $retval == $ERRORS{'OK'} ) {
			$retval = $ERRORS{'UNKNOWN'};
		}
	}
}

$session->close;

print $retmessage;
exit($retval);
