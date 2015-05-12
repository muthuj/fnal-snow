package FNAL::SNOW::Ticket::RITM;

=head1 NAME

FNAL::SNOW::RITM - work with SNOW Requested Items (RITMs)

=head1 SYNOPSIS

  [...]

=head1 DESCRIPTION

RITMS - Requested Items - are generated from Request tickets.  They are fairly
non-standard and are meant to be opened and closed quickly.  This library
should provide some tools to manipulate them.

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

use Data::Dumper;

use FNAL::SNOW::Ticket;
our @ISA = qw/FNAL::SNOW::Ticket/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

These subroutines were originally designed to manipulate Incidents, but are a
good start for dealing with all forms of tickets.

=over 4

=item assign (I<NUMBER>, I<GROUP>, I<USER>)

Assigns ticket I<NUMBER> to a given group and/or user.  If we are given a blank
value for I<USER>, we will clear the assignment field.  Returns an array of
updated Incident hashrefs (hopefully just one!).

=cut

sub assign {
    my ($self, $group, $user) = @_;

    my %update = ();
    if ($group)        { $update{'assignment_group'} = $group }
    if (defined $user) { $update{'assigned_to'}    = $user || 0 }

    return $self->update (%update);
}

### TODO: better build_filter for RITMs

=item list_by_type (I<TYPE>, I<SEARCH>, I<EXTRA>)

Performs an I<TYPE> query, and returns an array of matching hashrefs.  This
query is against the table associated with I<TYPE> (incidents, requests,
request items, and tasks), using the parameters in the hashref I<SEARCH> and
(if present) the extra parameters in I<EXTRA> against the F<__encoded_query>
field.  (The last part must be pre-formatted; use this at your own risk!)

=cut

sub list_by_type {
    my ($self, $type, $search, $extra) = @_;
    $type = $self->_type ($type);
    if ($extra) { $$search{'__encoded_query'} = $extra }
    my @entries = $self->query($type, $search);
    return @entries;
}

=item list_by_assignee (I<TYPE>, I<EXTRA>)

Queries for incidents assigned to the user I<NAME>.  Returns an array of
matching entries.

=cut

sub list_by_assignee {
    my ($self, $type, $user, $extra) = @_;
    $self->list_by_type ( $type, { 'assigned_to' => $user }, $extra )
}

##############################################################################
### Generic Ticket Actions ###################################################
##############################################################################

=head2 Generic Ticket Actions

These should ideally work against incidents, tasks, requests, etc.

=over 4

=item by_number

Queries for the ticket I<NUMBER> (after passing that field through
B<parse_ticket_number()> for consistency and to figure out what kind of ticket
we're looking at).  Returns an array of matching entries.

=cut

sub by_number {
    my ($self, $number) = @_;
    my $num = $self->parse_ticket_number ($number);
    my $type = $self->_type_by_number ($num);
    return $self->search ($type, { 'number' => $num });
}

=item create (TICKETHASH)

Creates a new ticket of type I<TYPE>, and returns the number of the created
ticket (or undef on failure).

(DOES NOT WORK FOR RITMS - we need to make a REQ first, I guess)

=cut

sub create {
    my ($self, %ticket) = @_;
    my @items = $self->create ($self->type, \%ticket);
    return undef unless (@items && scalar @items == 1);
    return $items[0]->{number};
}

=item is_resolved (TICKETHASH)

Returns 1 if the ticket is resolved, 0 otherwise.

NOT WORKING

=cut

sub is_resolved { return _state (@_) >= 4 ? 1 : 0 }

=item reopen

Update the ticket to set the incident_state back to 'Work In Progress',
and (attempts to) clear I<close_code>, I<close_notes>, I<resolved_at>,
and I<resolved_by>.

Uses B<update()>.

=cut

sub reopen {
    my ($self, $code, %args) = @_;
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

Updates the ticket to status 'resolved', as well as the following fields
based on I<ARGUMENT_HASH>:

   close_code       The resolution code (which can be anything, but FNAL has
                    a set list that they want it to be)
   text             Text to go in the resolution text.
   user             Set 'resolved_by' to this user.

Uses B<update()>.

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

=item update (CODE, ARGUMENTS)

Update the ticket, incident, or task associated with the string I<CODE>.
Uses B<update()>, with a hash made of I<ARGUMENTS>.

=cut

sub update {
    my ($self, $code, %args) = @_;
    return SUPER::update ($self, $self->type, { 'number' => $code }, \%args);
}

=back

=cut

=item type, type_pretty, type_short

I<sc_req_item>, I<requested item>, I<ritm>

=cut

sub type        { 'sc_req_item' }
sub type_pretty { 'requested item' }
sub type_short  { 'ritm' }

##############################################################################
### Generic Ticket Reporting #################################################
##############################################################################

=head2 Generic Ticket Reporting

These should ideally work against incidents, tasks, requests, etc.

=over 4

=item string_assignee (TKT)

Generates a report of the assignee information.

=cut

sub string_assignee {
    my ($self, $tkt) = @_;
    my @return = "Assignee Info";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Group'         => $self->_assigned_group ($tkt),
        'Name'          => $self->_assigned_person ($tkt),
        'Last Modified' => $self->_format_date ($self->_date_update($tkt))
    );
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
        'Status'        => $self->_status  ($tkt),
        'Approval'      => $self->_approval ($tkt),
        'Submitted'     => $self->_format_date ($self->_date_submit($tkt)),
        'Urgency'       => $self->_urgency ($tkt),
        'Priority'      => $self->_priority ($tkt),
        'Request'       => $self->_request ($tkt),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_requestor (TICKET)

Generates a report describing the requestor of the ticket.

=cut

sub string_requestor {
    my ($self, $tkt) = @_;
    my @return = "Requestor Info";

    my $requestor = $self->user_by_username ($self->_requestor($tkt));
    my $creator   = $self->user_by_name ($self->_opened_by($tkt));

    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'       => $$requestor{'dv_name'},
        'Email'      => $$requestor{'dv_email'},
        'Opened By'  => $$creator{'dv_email'}
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_resolution (TICKET)

Generates a report showing the resolution status.

=cut

sub string_resolution {
    my ($self, $tkt) = @_;
    my @return = "Resolution";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Resolved By' => $self->_resolved_by ($tkt),
        'Date'        => $self->_format_date ($self->_date_resolved($tkt)),
        'Close Code'  => $self->_resolved_code ($tkt)
    );
    push @return, '', $self->_format_text ({'prefix' => '  '},
        $self->_resolved_text($tkt));
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_short (TICKET)

Like string_basic(), but dropping the worklog.

=cut

sub string_short {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->string_primary     ($tkt);
    push @return, '', $self->string_requestor   ($tkt);
    push @return, '', $self->string_assignee    ($tkt);
    push @return, '', $self->string_description ($tkt);
    if ($self->is_resolved ($tkt)) {
        push @return, '', $self->string_resolution ($tkt);
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=item summary (RESULT [, RESULT [, RESULT [...]]])

Based on a number of FNAL::SNOW::QueryResult entries, generates a report
showing a human-readable summary of the tickets, suitable for presenting in list
form.

=cut

sub summary {
    my ($self, @tickets) = @_;
    my @return;

    foreach my $item (@tickets) {
        my $tkt = $item->result;

        my $createdby = $self->user_by_name ($self->_caller_id($tkt));
        unless ($createdby) {
            $createdby = $self->user_by_username ($self->_requestor($tkt)) || {};
        }

        my $assignedto = {};
        my $aid = $self->_assigned_person ($tkt);
        if ($aid ne '(none)') {
            $assignedto = $self->user_by_name ($aid);
        }

        my $inc_num     = _incident_shorten ($self->_number ($tkt));
        my $request     = $createdby->{'dv_user_name'} || '*unknown*';
        my $assign      = $assignedto->{'dv_user_name'} || '*unassigned*';
        my $group       = $self->_assigned_group ($tkt);
        my $status      = $self->_status ($tkt)
                            || $self->_itil_state ($tkt)
                            || $self->_stage ($tkt);
        my $created     = $self->_format_date ($self->_date_submit ($tkt));
        my $updated     = $self->_format_date ($self->_date_update ($tkt));
        my $description = $self->_summary ($tkt);

        push @return, sprintf ($SUMMARY_LINE1,
            $inc_num, $request, $assign, $group, $status );
        push @return, sprintf ($SUMMARY_LINE2, $created, $updated);
        push @return, sprintf ($SUMMARY_LINE3, $description);
    }
    return wantarray ? @return : join ("\n", @return);
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _incident_shorten (INC)
# Trims off the leading 'INC' and leading 0s.

sub _incident_shorten {
    my ($inc) = @_;
    $inc =~ s/^(INC|RITM|TASK|TKT)0+/$1/;
    return $inc;
}

### _* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash, or a suitable
# default value.  Should be fairly self-explanatory.

sub _approval { $_[1]{'dv_approval'} || '(none)'    }
sub _request  { $_[1]{'dv_request'}  || '(none)'    }

sub _assigned_group  { $_[1]{'dv_assignment_group'}  || '(none)'    }
sub _assigned_person { $_[1]{'dv_assigned_to'}       || '(none)'    }
sub _caller_id       { $_[1]{'dv_caller_id'} || $_[1]{'caller_id'} || '' }
sub _date_resolved   { $_[1]{'dv_resolved_at'}       || ''          }
sub _date_submit     { $_[1]{'dv_opened_at'}         || ''          }
sub _date_update     { $_[1]{'dv_sys_updated_on'}    || ''          }
sub _description     { $_[1]{'description'}          || ''          }
sub _itil_state      { $_[1]{'u_itil_state'}         || ''          }
sub _number          { $_[1]{'number'}               || '(none)'    }
sub _opened_by       { $_[1]{'dv_opened_by'}         || '(unknown)' }
sub _priority        { $_[1]{'dv_priority'}          || '(unknown)' }
sub _requestor       { $_[1]{'dv_sys_created_by'}    || '(unknown)' }
sub _resolved_by     { $_[1]{'dv_resolved_by'}       || '(none)'    }
sub _resolved_code   { $_[1]{'close_code'}           || '(none)'    }
sub _resolved_text   { $_[1]{'close_notes'}          || '(none)'    }
sub _stage           { $_[1]{'stage'}                || ''          }
sub _state           { $_[1]{'incident_state'}       || 0           }
sub _status          { $_[1]{'dv_u_itil_state'}       || '' }
sub _summary         { $_[1]{'dv_short_description'} || '(none)'    }
sub _svctype         { $_[1]{'u_service_type'}       || '(unknown)' }
sub _urgency         { $_[1]{'dv_urgency'}           || '(unknown)' }

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<FNAL::SNOW::Ticket>

=head1 SEE ALSO

B<FNAL::SNOW::Incident>

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014-2015, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
