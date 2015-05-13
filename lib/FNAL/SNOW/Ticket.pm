package FNAL::SNOW::Ticket;

=head1 NAME

FNAL::SNOW::Ticket - template for various SNOW ticket types

=head1 SYNOPSIS

  use FNAL::SNOW::Ticket;

=head1 DESCRIPTION

FNAL::SNOW::Ticket is a top-level template for interacting with different
Service Now (SNOW) ticket types - incidents, requested items, tasks, etc.  It
provides central functionality that is used by its various sub-classes.

All of the sub-classes of FNAL::SNOW::Ticket - ::Incident, ::RITM, etc -
include all of the main functions.  They can override the functions if
necessary, but this module provides basic functionality.

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

use Class::Struct;
use Data::Dumper qw/Dumper/;
use Date::Manip qw/UnixDate/;
use Text::Wrap;

use FNAL::SNOW;
use POSIX qw/strftime/;
use ServiceNow::Configuration;

struct 'FNAL::SNOW::Ticket' => {
    'connection' => '$'
};

use vars qw/%GROUPCACHE %USERCACHE %NAMECACHE/;

##############################################################################
### Subroutines ##############################################################
##############################################################################

##############################################################################
### Upstream Subroutines ###############################################
##############################################################################

=head2 Upstream 

=over 4

=item debug

Is debugging turned on upstream?  True/false.

=cut

sub debug { $_[0]->connection->debug }

=item snconf

Link back to the B<FNAL::SNOW> object that spawned this object.

=cut

sub snconf { $_[0]->connection->snconf }

=back

##############################################################################
### Database Subroutines #####################################################
##############################################################################

=head2 Database Subroutines

These subroutines perform direct database queries, using
B<ServiceNow::GlideRecord>.

=over 4

=item build_filter (I<ARGHASH>)

Generates the text and "__encoded_query" search terms associated with ticket
searches.  We currently support:

   submit_before  (INT)       opened_at < YYYY-MM-DD HH:MM:SS
   unassigned     (true)      assigned_to=NULL

Additionally, we call B<build_filter_extra()> first, so that each sub-class can
implement its own additional filters.

Returns two strings: the EXTRA query and the TEXT associated with the search.

=cut

sub build_filter {
    my ($self, %args) = @_;

    my $submit_before = $args{'submit_before'} || '';
    my $unassigned    = $args{'unassigned'}    || 0;

    my $type = $self->type_short;

    my ($text, @extra) = $self->build_filter_extra(%args);

    if ($unassigned) {
        $text = "Unassigned $text";
        push @extra, 'assigned_to=NULL';
    }

    if ($submit_before) {
        my $time = strftime ("%Y-%m-%d %H:%M:%S %Z", localtime ($submit_before));
        $text  = "$text submitted before $time";
        push @extra, "opened_at<$time";
    }
    return (join ('^', @extra), $text);

}

=item build_filter_extra (I<ARGHASH>)

Takes the same argument hash as B<build_filter()>, but can be overridden by
other functions.

=cut

sub build_filter_extra { "", () }

=item create (TABLE, PARAMS)

Inserts a new item into the Service Now database in table I<TABLE> and based
on the parameters in the hashref I<PARAMS>.  Returns the matching items (as
pulled from another query based on the returned sys_id).

=cut

sub create_bad {
    my ($self, $table, $params) = @_;
    my $glide = ServiceNow::GlideRecord->new ($self->snconf, $table);
    my $id = $glide->insert ($params);
    return unless $id;
    return $self->query ($table, {'sys_id' => $id} )
}

sub insert { create (@_) }

=item query (TABLE, PARAMS)

Queries the Service Now database, looking specifically at table I<TABLE> with
parameters stored in the hashref I<PARAMS>.  Returns an array of matching
B<FNAL::SNOW::Query> objects, one for each matching entry.

=cut

sub query { shift->connection->query (@_) }

=back

=cut

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
    my ($self, $number, $group, $user) = @_;

    my %update = ();
    if ($group)        { $update{'assignment_group'} = $group }
    if (defined $user) { $update{'assigned_to'}    = $user || 0 }

    return $self->update ($number, %update);
}

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

=item parse_ticket_number (NUMBER)

Standardizes an incident number into the 15-character string starting with
'INC' (or similar).

=cut

sub parse_ticket_number {
    my ($self, $num) = @_;
    return $num if $num && $num =~ /^(INC|REQ)/ && length ($num) == 15;
    return $num if $num && $num =~ /^(TASK|RITM)/ && length ($num) == 11;

    $num ||= "";
    if ($num =~ /^(INC|REQ)(\d+)$/) {
        $num = join ('', $1, ('0' x (15 - length ($num))), $2);
    } elsif ($num =~ /^(TASK|RITM)(\d+)$/) {
        $num = join ('', $1, ('0' x (11 - length ($num))), $2);
    } elsif ($num =~ /^(\d+)/) {
        $num = join ('', 'INC', ('0' x (12 - length ($num))), $1);
    } else {
        return;
    }
    return $num;
}


=item type, type_pretty, type_short

These informational functions provide the table name, a pretty version of the
table name, and a short version of the table name.  They should be overridden
by sub-classes.  Default for all is 'unknown'.

=cut

sub type        { 'unknown' }
sub type_pretty { 'unknown' }
sub type_short  { 'unknown' }

=back

=cut

##############################################################################
### Incident Lists ###########################################################
##############################################################################

=head2 Ticket Lists

These functions generate an array of ticket objects, and pass them through
B<tkt_list()> to generate human-readable reports.  Each of them either returns
an array of lines suitable for printing, or (in a scalar syntax) a single
string with built-in newlines.

=over 4


=cut

##############################################################################
### Generic Ticket Actions ###################################################
##############################################################################

=head2 Generic Ticket Actions

These require an active connection to SNOW.  These should ideally work against 
incidents, tasks, requests, etc.

=over 4

=item create (TYPE, TKTHASH)

Creates a new ticket of type I<TYPE>, and returns the number of the created
ticket (or undef on failure).

=cut

sub create { return 'unsupported' }

=item is_resolved (CODE)

Returns 1 if the ticket is resolved, 0 otherwise.

=cut

sub is_resolved { warn "is_resolved: unsupported\n"; return 0 }

=item list (TEXT, TICKETLIST)

Given a list of B<FNAL::SNOW::QueryResult> objects, sorts them by number,
pushes them all through B<summary()> to get text, and combines the text into a
single object.  Returns either an array of lines of text, or a single string
with those lines combined with newlines.

=cut

sub list {
    my ($self, $text, @list) = @_;

    my %entries;
    foreach my $item (@list) {
        my $result  = $item->result or next;
        my $number  = $result->{'number'} or next;

        my $summary = $self->summary ($item);
        $entries{$number} = $summary;
    }

    my @return;
    push @return, $text, '';
    foreach (sort { $a cmp $b } keys %entries) {
        push @return, ($entries{$_}, '')
    }
    wantarray ? @return : join ("\n", @return, '');
}

=item reopen

Reopen a ticket.  Not supported by default.

=cut

sub reopen { return 'unsupported' }

=item resolve ( CODE, ARGUMENT_HASH )

Resolve a ticket.  Not supported by default.

=cut

sub resolve { 'unsupported' }

=item search (SEARCH, EXTRA)

Search for a ticket.

=cut

sub search {
    my ($self, $search, $extra) = @_;
    if ($extra) { $$search{'__encoded_query'} = $extra }
    return $self->query ($self->type, $search);
}

=item update (CODE, ARGUMENTS)

Update the ticket, incident, or task associated with the string I<CODE>.
Uses the upstream B<update()>, with a hash made of I<ARGUMENTS>.

=cut

sub update {
    my ($self, $code, %args) = @_;
    return $self->connection->update ($self->type, 
        { 'number' => $code }, \%args);
}

=back

=cut

##############################################################################
### Generic Ticket Reporting #################################################
##############################################################################

=head2 Generic Ticket Reporting

These should ideally work against incidents, tasks, requests, etc.

=over 4

=item tkt_list (TEXT, TICKETLIST)

Given a list of ticket objects, sorts them by number, pushes them all
through B<tkt_summary()>, and combines the text into a single object.

=cut

sub tkt_list {
    my ($self, $text, @list) = @_;
    my @return;
    push @return, $text, '';
    foreach (sort { $a->{'number'} cmp $b->{'number'} } @list) {
        push @return, ($self->tkt_summary ($_), '')
    }
    wantarray ? @return : join ("\n", @return, '');
}

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
    push @return, '', $self->string_description ($tkt);
    if (my @journal = $self->string_journal ($tkt)) {
        push @return, '', @journal;
    }
    if ($self->is_resolved ($tkt)) {
        push @return, '', $self->string_resolution ($tkt);
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=item string_debug (TICKET)

Generates a report showing the content of every field (empty or not).

=cut

sub string_debug {
    my ($self, $tkt) = @_;
    my @return;
    push @return, "== " . $$tkt{'sys_id'};
    foreach my $key (sort keys %$tkt) {
        push @return, Text::Wrap::wrap ('', ' ' x 41, sprintf ("  %-33s  %-s",
            $key, $$tkt{$key} || '(empty)'));
    }
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_description (TICKET)

Generates a report showing the user-provided description.

=cut

sub string_description {
    my ($self, $tkt) = @_;
    my @return = "User-Provided Description";
    push @return, $self->_format_text ({'prefix' => '  '},
            $self->_description ($tkt));
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_journal (TICKET)

Generates a report showing all journal entries associated with this ticket, in
reverse order (blog style).

=cut

sub string_journal {
    my ($self, $tkt) = @_;
    my @return = "Journal Entries";
    my @entries = $self->_journal_entries ($tkt);
    if (scalar @entries < 1) { return '' }

    my $count = scalar @entries;
    foreach my $entry (reverse @entries) {
        my $journal = $entry->result;
        push @return, "  Entry " . $count--;
        push @return, $self->_format_text_field (
            {'minwidth' => 20, 'prefix' => '    '},
            'Date'       => $self->_format_date(
                                $self->_journal_date ($journal), 'GMT'),
            'Created By' => $self->_journal_author ($journal),
            'Type'       => $self->_journal_type   ($journal),
        );
        push @return, '';
        push @return, $self->_format_text ({'prefix' => '    '},
            $self->_journal_text($journal));
        push @return, '' unless $count == 0;
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
        'Status'        => $self->_status  ($tkt),
        'Submitted'     => $self->_format_date ($self->_date_submit($tkt)),
        'Urgency'       => $self->_urgency ($tkt),
        'Priority'      => $self->_priority ($tkt),
        'Service Type'  => $self->_svctype ($tkt),
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
    my $createdby = $self->user_by_name ($self->_caller_id($tkt));

    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'       => $$createdby{'name'},
        'Email'      => $$createdby{'email'},
        'Created By' => $$requestor{'name'} || $self->_opened_by ($tkt),
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

Like string_basic(), but dropping the worklog and description.

=cut

sub string_short {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->string_primary     ($tkt);
    push @return, '', $self->string_requestor   ($tkt);
    push @return, '', $self->string_assignee    ($tkt);
    if ($self->is_resolved ($tkt)) {
        push @return, '', $self->string_resolution ($tkt);
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
        my $createdby  = $self->user_by_name ($cid);
        unless ($createdby) {
            my $rid = $self->_requestor($tkt);
            $createdby = $self->user_by_username ($rid) || {};
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
            $inc_num, $request, $assign, $group, $status);
        push @return, sprintf ($SUMMARY_LINE2, $created, $updated);
        push @return, sprintf ($SUMMARY_LINE3, $description);
    }
    return wantarray ? @return : join ("\n", @return);
}

=back

=cut

##############################################################################
### User and Group Subroutines ###############################################
##############################################################################

=head2 Users and Groups

These are wrappers around the main functions in B<FNAL::SNOW>.

=over 4

=item user_by_name (I<NAME>)

=cut

sub user_by_name { shift->connection->user_by_name (@_) }

=item user_by_sysid (I<ID>)

=cut

sub user_by_sysid { shift->connection->user_by_sysid (@_) }

=item user_by_username (I<NAME>)

=cut

sub user_by_username { shift->connection->user_by_username (@_) }

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

### _format_date (SELF, TIME)
# Generate a datetime from TIME.  If TIME is an INT, assume that it's
# seconds-since-epoch; if it's a string, parse it with UnixDate to get
# seconds-since-epoch; if we can

sub _format_date {
    my ($self, $time, $zone) = @_;
    if ($time =~ /^\d+$/) { }   # all is well
    elsif ($time) { $time = UnixDate ($time || time, '%s'); }
    return $time ? strftime ("%Y-%m-%d %H:%M:%S %Z", localtime($time))
                 : sprintf ("%-20s", "(unknown)");
}

### _format_text (SELF, ARGHASH, TEXT)
# Uses Text::Wrap to wrap TEXT.  ARGHASH provides parameters necessary for
# Text::Wrap.  ARGHASH fields:
#
#    prefix     Prefix characters (generally '', '  ', or '    ')
#
# Returns an array of lines, or (as a scalar) a single string joined with
# newlines.

sub _format_text {
    my ($self, $args, @print) = @_;
    $args ||= {};

    my $prefix = $$args{'prefix'}   || '';

    my @return = wrap ($prefix, $prefix, @print);
    return wantarray ? @return : join ("\n", @return, '');
}

### _format_text_field (SELF, ARGHASH, TEXTFIELDS)
# Uses Text::Wrap to print wrapped text fields.  Specifically TEXTFIELDS
# should contain pairs of field/value pairs.  ARGHASH fields:
#
#    minwidth   How big should the 'field' section be?  Generally ~30
#               characters.
#    prefix     Prefix characters (generally '', '  ', or '    ')
#
# Returns an array of lines, or (as a scalar) a single string joined with
# newlines.

sub _format_text_field {
    my ($self, $args, @print) = @_;
    $args ||= {};

    my $prefix = $$args{'prefix'}   || '';
    my $width  = $$args{'minwidth'} || 0;

    my (@return, @entries);

    while (@print) {
        my ($field, $text) = splice (@print, 0, 2);
        $field = "$field:";
        push @entries, [$field, $text || "*unknown*"];
        $width = length ($field) if length ($field) > $width;
    }

    foreach my $entry (@entries) {
        my $field = '%-' . $width . 's';
        push @return, wrap ($prefix, $prefix . ' ' x ($width + 1),
            sprintf ("$field %s", @{$entry}));
    }

    return wantarray ? @return : join ("\n", @return, '');
}

### _incident_shorten (INC)
# Trims off the leading 'INC' and leading 0s.

sub _incident_shorten {
    my ($inc) = @_;
    $inc =~ s/^(INC|RITM|TASK|TKT|REQ)0+/$1/;
    return $inc;
}

### _journal_* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash.

sub _journal_author { $_[1]{'dv_sys_created_by'} || '(unknown)' }
sub _journal_date   { $_[1]{'dv_sys_created_on'} || '(unknown)' }
sub _journal_text   { $_[1]{'dv_value'}          || ''          }
sub _journal_type   { $_[1]{'dv_element'}        || ''          }

### _journal_entries (SELF, TKT)
# List all journal entries associated with this object, sorted by date.

sub _journal_entries {
    my ($self, $tkt) = @_;
    my (@return, %entries);
    foreach my $j ($self->query ('sys_journal_field',
        { 'element_id' => $tkt->{'sys_id'} })) {
        my $entry = $j->result;
        my $key = $self->_journal_date($entry);
        $entries{$key} = $j;
    }
    foreach (sort keys %entries) { push @return, $entries{$_} }

    return @return;
}

### _tkt_* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash, or a suitable
# default value.  Should be fairly self-explanatory.

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
sub _sys_created_by  { $_[1]{'dv_sys_created_by'}    || '(none)'    }
sub _stage           { $_[1]{'dv_stage'}  || $_[1]{'stage'} || ''   }
sub _state           { $_[1]{'incident_state'}       || 0           }
sub _status          { $_[1]{'dv_incident_state'}    || '' }
sub _summary         { $_[1]{'dv_short_description'} || '(none)'    }
sub _svctype         { $_[1]{'u_service_type'}       || '(unknown)' }
sub _urgency         { $_[1]{'dv_urgency'}           || '(unknown)' }

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
