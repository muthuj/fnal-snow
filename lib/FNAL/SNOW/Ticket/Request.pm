package FNAL::SNOW::Ticket::Request;

=head1 NAME

FNAL::SNOW::Ticket::Request - Service Now Requests

=head1 SYNOPSIS

  use FNAL::SNOW::Ticket::Request;

=head1 DESCRIPTION

Requests are occasionally used within Service Now.  This library should
provide some tools to manipulate them, primarily based on the standard Ticket
items.

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
use FNAL::SNOW::Ticket::RITM;
our @ISA = qw/FNAL::SNOW::Ticket/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

See B<FNAL::SNOW::Ticket> for most functions.

=over 4

=item string_base (TICKET)

Generates a combined report, with the primary, requestor, assignee,
description, journal (if present), and resolution status (if present).

=cut

sub string_base {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->string_primary     ($tkt);
    push @return, '', $self->string_requestor   ($tkt);
    push @return, '', $self->string_assignee    ($tkt);
    if (my @ritms = $self->string_ritms ($tkt)) {
        push @return, '', @ritms;
    }
    if ($self->is_resolved ($tkt)) {
        push @return, '', $self->string_resolution ($tkt);
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=item string_primary (TICKET)

Generates a report on the "primary" information for a ticket - number, text
summary, status, submitted date, urgency, priority, and service type.

=cut

sub string_primary {
    my ($self, $tkt) = @_;
    my @return = "Primary Ticket Information";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Number'        => $self->_number  ($tkt),
        'Summary'       => $self->_summary ($tkt),
        'Status'        => $self->_itil_state ($tkt),
        'Stage'         => $self->_stage   ($tkt),
        'Submitted'     => $self->_format_date ($self->_date_submit($tkt)),
        'Urgency'       => $self->_urgency ($tkt),
        'Priority'      => $self->_priority ($tkt),
        'Request Type'  => $self->_reqtype ($tkt),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_requestor (TICKET)

Generates a report describing the requestor of the ticket.

=cut

sub string_requestor {
    my ($self, $tkt) = @_;
    my @return = "Requestor Info";

    my $requestor = $self->user_by_sysid ($self->_requestor($tkt));
    my $createdby = $self->user_by_sysid ($self->_caller_id($tkt));

    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'       => $$requestor{'name'},
        'Email'      => $$requestor{'email'},
        'Created By' => $$createdby{'name'} || $self->_caller_id ($tkt),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_ritms (TICKET)

Generates a standard list report of all requested items (RITMs) associated with
this request.

=cut

sub string_ritms {
    my ($self, $tkt) = @_;
    my @return = "Associated Requested Items (RITMs)";
    my @ritms = $self->connection->tkt_list_by_type ('ritm',
        { 'request' => $tkt->{'sys_id'} } );
    push @return, '' if (scalar @ritms);

    my $obj = FNAL::SNOW::Ticket::RITM->new ('connection' => $self->connection);
    foreach my $ritm (@ritms) {
        push @return, $obj->summary($ritm);
    }
    return wantarray ? @return : join ("\n", @return, '');
}

=item summary ( TICKET [, TICKET [, TICKET [...]]] )

Generates a report showing a human-readable summary of a series of tickets,
suitable for presenting in list form.

=cut

sub summary {
    my ($self, @tickets) = @_;
    my @return;

    foreach my $item (@tickets) {
        my $tkt = $item->result;
        my $cid = $self->_caller_id ($tkt);
        # my $createdby  = $self->user_by_sysid ($cid);
        # unless ($createdby) {
            # my $rid = $self->_requestor($tkt);
            # $createdby = $self->user_by_sysid ($rid) || {};
        # }
# 
        # my $assignedto = {};
        # my $aid = $self->_assigned_person ($tkt);
        # if ($aid ne '(none)') {
            # $assignedto = $self->user_by_name ($aid);
        # }

        my $inc_num     = FNAL::SNOW::Ticket::_incident_shorten ($self->_number ($tkt));
        # my $request     = $createdby->{'dv_user_name'} || '*unknown*';
        # my $assign      = $assignedto->{'dv_user_name'} || '*unassigned*';
        my $request     = '*unknown*';
        my $assign      = '*unassigned*';
        my $group       = $self->_assigned_group ($tkt);
        my $status      = $self->_status ($tkt)
                            || $self->_itil_state ($tkt)
                            || $self->_stage ($tkt);
        my $created     = $self->_format_date ($self->_date_submit ($tkt));
        my $updated     = $self->_format_date ($self->_date_update ($tkt));
        my $description = $self->_summary ($tkt);

        push @return, sprintf ($SUMMARY_LINE1,
            $inc_num, $request, $assign, $group, $status);
        push @return, sprintf ($SUMMARY_LINE2, $created, $updated);
        push @return, sprintf ($SUMMARY_LINE3, $description);
    }
    return wantarray ? @return : join ("\n", @return);
}


=item type, type_pretty, type_short

I<sc_request>, I<request>, I<request>

=cut

sub type        { 'sc_request' }
sub type_pretty { 'request' }
sub type_short  { 'request' }

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _requestor { $_[1]{'opened_by'}      || '(unknown)' }
sub _reqtype   { $_[1]{'u_request_type'} || '(unknown)' }
sub _caller_id { $_[1]{'requested_for'}  || '(unknown)' }


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
