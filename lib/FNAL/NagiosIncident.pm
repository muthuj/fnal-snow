package FNAL::NagiosIncident;

=head1 NAME

FNAL::NagiosIncident -

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

struct 'FNAL::NagiosIncident' => {
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

=item create

=cut

sub create {
    my ($self, $sname) = @_;
    unless (ref $self) { $self = $self->new }
    my $file = join ('/', $BASEDIR, "${sname}.incident");
    $self->filename ($file);
    $self->sname ($sname);
    return $self;
}

=item filename

=item incident

=item read

=cut

sub read {
    my $self = create (@_);
    my $file = $self->filename;
    open (IN, '<', $file)
        or ( warn "could not read $file: $@\n" && return undef );
    while (my $line = <IN>) {
        chomp $line;
        if ($line =~ /^ACK=(.*)$/)   { $self->ack ($1) }
        if ($line =~ /^INC=(.*)$/)   { $self->set_incident ($1) }
        if ($line =~ /^SNAME=(.*)$/) { $self->sname ($1) }
    }
    close IN;

    return $self;
}

=item read_dir

=cut

sub read_dir {
    my ($self, $dir) = @_;
    opendir (my $dh, $dir) or die "could not open $dir: $@\n";
    my @files = grep { /\.incident$/ } readdir $dh;
    closedir $dh;
    my @incidents;
    foreach my $file (@files) {
        my ($f) = $file =~ /^(.*).incident$/;
        my $inc = $self->read ($f);
        push @incidents, $inc if $inc;
    }
    return @incidents;
}

=item set_incident

=cut

sub set_incident {
    my ($self, $number) = @_;
    unless (ref $self) { $self = $self->new }
    $self->incident (_incnumber_long($number));
    return $self->incident;
}

=item sname

=item unlink

=cut

sub unlink {
    my ($self) = @_;
    unless (ref $self) { $self = $self->read (@_) }
    unlink $self->filename;
}

=item write

=cut

sub write {
    my ($self) = @_;
    my $file = $self->filename;
    open (OUT, '>' . $file) or die "could not write to $file: $@\n";
    print OUT sprintf ("INC=%s\n",   ($self->incident || ''));
    print OUT sprintf ("ACK=%s\n",   ($self->ack || ''));
    print OUT sprintf ("SNAME=%s\n", ($self->sname || ''));
    close OUT;
    chmod 0600, $file;
    return;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _incnumber_short {
    my ($inc) = @_;
    $inc =~ s/^(INC)?0+//;
    return $inc;
}

sub _incnumber_long {
    my ($incident) = @_;
    my ($number) = $incident =~ /^(?:INC)?(\d+)$/;
    unless ($number) { return undef }
    return sprintf ("INC%012d", $number);
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
