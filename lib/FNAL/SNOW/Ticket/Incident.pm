package FNAL::SNOW::Ticket::Incident;

=head1 NAME

FNAL::SNOW::Ticket::Incident - Service Now Incidents

=head1 SYNOPSIS

  use FNAL::SNOW::Ticket::Incident;

=head1 DESCRIPTION

Incidents are the standard unit of work in Service Now.  This library should
provide some tools to manipulate them.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $SUMMARY_LINE1 = "%-12.12s %-14.14s %-14.14s %-17.17s %17.17s";
our $SUMMARY_LINE2 = " Created: %-24.24s            Updated: %-24.24s";
our $SUMMARY_LINE3 = " Subject: %-68.68s";

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use FNAL::SNOW::Ticket;
our @ISA = qw/FNAL::SNOW::Ticket/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item build_filter_extra (I<ARGHASH>)

Adds additional search filters for building queries.  We currently support:

   subtype        open        incident_state < 4
                  closed      incident_state >= 4
                  unresolved  incident_state < 7
                  other       (no filter)

=cut

sub build_filter_extra {
    my ($self, %args) = @_;

    my $type = $self->type_short;
    my $subtype = $args{'subtype'} || "";

    my ($text, @extra);
    if      (lc $subtype eq 'open') {
        $text  = "Open ${type}s";
        push @extra, "incident_state<4";
    } elsif (lc $subtype eq 'closed') {
        $text = "Closed ${type}s";
        push @extra, 'incident_state>=4';
    } elsif (lc $subtype eq 'unresolved') {
        $text = "Unresolved ${type}s";
        push @extra, 'incident_state<7';
    } elsif (defined ($subtype)) {
        $text = "All ${type}s"
    }

    return ($text, @extra);
}

=item is_resolved (TICKET)

Returns 1 if the ticket is resolved, 0 otherwise.  In the case of Incidents,
this means "the state is >= 4", which is fairly anachronistic.

=cut

sub is_resolved {
    my ($self, $tkt) = @_;
    return $self->_state($tkt) >= 4 ? 1 : 0
}

=item reopen

Update the incident_state back to 'Work In Progress', and (attempts to) clear
I<close_code>, I<close_notes>, I<resolved_at>, and I<resolved_by>.

=cut

sub reopen {
    my ($self, $code) = @_;
    my %update = (
        'incident_state' => 2,      # 'Work In Progress'
        'close_notes'    => 0,
        'close_code'     => 0,
        'resolved_at'    => 0,
        'resolved_by'    => 0,
    );
    return $self->update ($code, %update);
}

=item resolve ( CODE, ARGUMENT_HASH )

Updates the incident to status 'resolved', as well as the following fields
based on I<ARGUMENT_HASH>:

   close_code       The resolution code (which can be anything, but FNAL has
                    a set list that they want it to be)
   text             Text to go in the resolution text.
   user             Set 'resolved_by' to this user.

=cut

sub resolve {
    my ($self, $code, %args) = @_;
    my %update = (
        'incident_state' => 6,      # 'Resolved'
        'close_notes'    => $args{'text'},
        'close_code'     => $args{'close_code'},
        'resolved_by'    => $args{'user'},
    );
    return $self->update ($code, %update);
}

=item type, type_pretty, type_short

I<incident>, I<incident>, I<incident>

=cut

sub type        { 'incident' }
sub type_pretty { 'incident' }
sub type_short  { 'incident' }

=item update (CODE, ARGUMENTS)

See B<FNAL::SNOW::Ticket> (may not be necessary)

=back

=cut

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<ServiceNow>

=head1 SEE ALSO

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014-2015, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
