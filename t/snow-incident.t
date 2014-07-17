#!/usr/bin/perl

##############################################################################
### Configuration ############################################################
##############################################################################

use lib '/home/tskirvin/rpm/cms-monitor/lib';

##############################################################################
### Declarations #############################################################
##############################################################################

use Test::More tests => 23;

use strict;
use warnings;

use File::Temp qw/tempdir/;
use Getopt::Long;
use SNOW::Incident;

##############################################################################
### Subroutines ##############################################################
##############################################################################

### error_usage (ERROR)
# Exit out with pod2usage.
sub error_usage {
    my ($error) = @_;
    pod2usage (-exit_status => 2, -verbose => 1);
}

##############################################################################
### main () ##################################################################
##############################################################################

my $tempdir = tempdir (CLEANUP => 1);
$SNOW::Incident::BASEDIR = $tempdir;

## Test create() and write() (and ack for good measure)
foreach my $num (qw/foo bar:baz/) {
    ok (my $incident = SNOW::Incident->create ($num),
        "created incident $num");
    ok ($incident->ack ("yes"), "updated ack in incident $num");
    eval { $incident->write };
    if ($@) { fail "could not write to $@\n" }
    else    { ok   (1, "wrote out $num") }
}

## Test read() and whether the write() gave what we wanted
foreach my $num (qw/foo/) {
    ok (my $incident = SNOW::Incident->read ($num), 
        "reading incident $num");
    ok ($incident->sname, "inc $num: sname is set");
    ok (!$incident->incident, "inc $num - incident is not set");
    like ($incident->ack, qr/yes/, "inc $num - ack is not set");
    ok ($incident->set_incident ('001'), "inc $num - setting incident");
    like ($incident->incident, qr/^INC0+001$/,
        "incident number $num is long");
    eval { $incident->write };
    if ($@) { fail "could not write to $@\n" }
    else    { ok   (1, "wrote out $num") }

    ok (my $inc2 = SNOW::Incident->read ($num), 
        "reading incident $num again");
    ok ($incident->incident, "inc $num - incident is set this time");
}

## test unlink()
foreach my $num (qw/foo bar:baz/) {
    ok (my $incident = SNOW::Incident->read ($num), 
        "reading $num");
    ok ($incident->unlink, "unlinking $num");
    if ($incident->unlink) { fail "inc $num - file not deleting?" }
    else                   { ok (1, "file is already gone") }

    my $inc2;
    eval { $inc2 = SNOW::Incident->read ($num) };
    if ($inc2) { fail "inc $num - file did not unlink: $@"  }
    else       { ok (1, "can no longer read from $num; $@") }
}
