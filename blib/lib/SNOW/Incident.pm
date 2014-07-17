package SNOW::Incident;

=head1 NAME

SNOW::Incident -

=head1 SYNOPSIS

=head1 DESCRIPTION

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $BASEDIR = '/srv/monitor/snow-incidents';

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;

struct 'SNOW::Incident' => {
    'ack'      => '$',
    'filename' => '$',
    'incident' => '$',
    'sname'    => '$',
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item ack

=item filename

=item incident

=item read

=cut

sub create { 
    my ($number) = @_;
    my $file = join ('/', $BASEDIR, _shorten_incident($number));
    my $self = SNOW::Incident->new;
    $self->filename($file);
    $self->incident($number);
    return $self;
}

sub incnumber_full {
    my ($incident) = @_;
    my ($number) = $incident =~ /^(?:INC)?(\d+)$/;
    unless ($number) { return undef }
    return sprintf ("INC%12d" % $number);
}

sub read {
    my $self = shift->create;
    my $file = $self->filename;
    open (IN, '<', $file) 
        or ( warn "could not read $file: $@\n" && return undef );
    while (my $line = <IN>) {
        chomp $line;
        if ($line =~ /^ACK=(.*)$/)   { $self->ack ($1) }
        if ($line =~ /^INC=(.*)$/)   { $self->incident ($1) }
        if ($line =~ /^SNAME=(.*)$/) { $self->sname ($1) }
    }
    close IN;

    return $self;
}

=item sname

=item unlink

=cut

sub unlink {
    my ($self) = @_;
    unlink $self->filename;
}

=item write

=cut

sub write {
    my ($self) = @_;
    my $file = $self->filename;
    open (OUT, '>' . $file) or die "could not write to $file: $@\n";
    print OUT sprintf ("INC=%s\n" % $self->incident);
    print OUT sprintf ("ACK=%s\n" % $self->ack);
    print OUT sprintf ("SNAME=%s\n" % $self->sname);
    close OUT;
    chmod 0600, $file;
    return;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _shorten_incident {
    my ($inc) = @_;
    $inc =~ s/^INC0+//;
    return $inc;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<Class::Struct>

=head1 SEE ALSO

B<snow-alert-create>

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>, based on code by Tyler Parsons
<tyler.parsons-fermilab@dynamicpulse.com>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
