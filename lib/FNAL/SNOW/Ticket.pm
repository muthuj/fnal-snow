package FNAL::SNOW::Ticket;

=head1 NAME

FNAL::SNOW::Ticket - template for various SNOW ticket types

=head1 SYNOPSIS

  [...]

=head1 DESCRIPTION

FNAL::SNOW::Ticket is a top-level template for interacting with different
Service Now (SNOW) ticket types - incidents, requested items, tasks, etc.  It
provides central functionality that is used by its various sub-classes.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

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
### Initiailization Subroutines ##############################################
##############################################################################

=over 4

=item snconf

=cut

sub snconf { $_[0]->connection->snconf }

=back

##############################################################################
### Database Subroutines #####################################################
##############################################################################

=head2 Database Subroutines

These subroutines perform direct database queries, using B<ServiceNow::GlideRecord>.

=over 4

=item create (TABLE, PARAMS)

Inserts a new item into the Service Now database in table I<TABLE> and based
on the parameters in the hashref I<PARAMS>.  Returns the matching items (as
pulled from another query based on the returned sys_id).

=cut

sub create {
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

=item update (TABLE, QUERY, UPDATE)

Updates Service Now objects in table I<TABLE> matching parameters from the
hashref I<QUERY>.  I<UPDATE> is a hashref containing updates.  Returns an
array of updated entries.

=cut

sub update_old {
    my ($self, $table, $query, $update) = @_;
    my $glide = ServiceNow::GlideRecord->new ($self->snconf, $table);
    $glide->query ($query);

    my @return;
    while ($glide->next()) {
        foreach (keys %$update) {
            $glide->setValue ($_, $$update{$_});
        }
        $glide->update();
        my %record = $glide->getRecord();
        push @return, \%record;
    }

    return @return;
}

=back

=cut

=head1 FUNCTIONS

These subroutines were originally designed to manipulate Incidents, but are a
good start for dealing with all forms of tickets.

=over 4

=item tkt_assign (I<NUMBER>, I<GROUP>, I<USER>)

Assigns ticket I<NUMBER> to a given group and/or user.  If we are given a blank
value for I<USER>, we will clear the assignment field.  Returns an array of
updated Incident hashrefs (hopefully just one!).

=cut

sub tkt_assign {
    my ($self, $number, $group, $user) = @_;

    my %update = ();
    if ($group)        { $update{'assignment_group'} = $group }
    if (defined $user) { $update{'assigned_to'}    = $user || 0 }

    return $self->tkt_update ($number, %update);
}

sub incident_assign { shift->tkt_assign ('Incident', @_) }

=item tkt_list_by_type (I<TYPE>, I<SEARCH>, I<EXTRA>)

Performs an I<TYPE> query, and returns an array of matching hashrefs.  This
query is against the table associated with I<TYPE> (incidents, requests,
request items, and tasks), using the parameters in the hashref I<SEARCH> and
(if present) the extra parameters in I<EXTRA> against the F<__encoded_query>
field.  (The last part must be pre-formatted; use this at your own risk!)

=cut

sub tkt_list_by_type {
    my ($self, $type, $search, $extra) = @_;
    $type = $self->_tkt_type ($type);
    if ($extra) { $$search{'__encoded_query'} = $extra }
    my @entries = $self->query($type, $search);
    return @entries;
}

=item tkt_list_by_assignee (I<TYPE>, I<EXTRA>)

Queries for incidents assigned to the user I<NAME>.  Returns an array of
matching entries.

=cut

sub tkt_list_by_assignee {
    my ($self, $type, $user, $extra) = @_;
    $self->tkt_list_by_type ( $type, { 'assigned_to' => $user }, $extra )
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

=item search (SEARCH, EXTRA)

Search for a ticket.  I<SEARCH> is a hashref containing all of the relevant
search terms; I<EXTRA> is an extra encoded query, to be added to the
search term, unassociated with the main search areas.  This is then passed into
B<query()>.

=cut

sub search {
    my ($self, $search, $extra) = @_;
    if ($extra) { $$search{'__encoded_query'} = $extra }
    return $self->query ($self->type, $search);
}

=item type, type_pretty, type_short

=cut

sub type        { 'incident' }
sub type_pretty { 'incident' }
sub type_short  { 'incident' }

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

=back

=cut

##############################################################################
### Generic Ticket Actions ###################################################
##############################################################################

=head2 Generic Ticket Actions

These should ideally work against incidents, tasks, requests, etc.

=over 4

=item tkt_create (

Creates a new ticket of type I<TYPE>, and returns the number of the created
ticket (or undef on failure).

=cut

sub tkt_create {
    my ($self, $type, %ticket) = @_;
    my @items = $self->create ($type, \%ticket);
    return undef unless (@items && scalar @items == 1);
    return $items[0]->{number};
}

=item tkt_is_resolved (CODE)

Returns 1 if the ticket is resolved, 0 otherwise.

=cut

sub tkt_is_resolved { return _tkt_state (@_) >= 4 ? 1 : 0 }

=item tkt_reopen

Update the ticket to set the incident_state back to 'Work In Progress',
and (attempts to) clear I<close_code>, I<close_notes>, I<resolved_at>,
and I<resolved_by>.

Uses B<tkt_update()>.

=cut

sub tkt_reopen {
    my ($self, $code, %args) = @_;
    my %update = (
        'incident_state' => 2,      # 'Work In Progress'
        'close_notes'    => 0,
        'close_code'     => 0,
        'resolved_at'    => 0,
        'resolved_by'    => 0,
    );
    return $self->tkt_update ($code, %update);
}

=item tkt_resolve ( CODE, ARGUMENT_HASH )

Updates the ticket to status 'resolved', as well as the following fields
based on I<ARGUMENT_HASH>:

   close_code       The resolution code (which can be anything, but FNAL has
                    a set list that they want it to be)
   text             Text to go in the resolution text.
   user             Set 'resolved_by' to this user.

Uses B<tkt_update()>.

=cut

sub tkt_resolve {
    my ($self, $code, %args) = @_;
    my %update = (
        'incident_state' => 6,      # 'Resolved'
        'close_notes'    => $args{'text'},
        'close_code'     => $args{'close_code'},
        'resolved_by'    => $args{'user'},
    );
    return $self->tkt_update ($code, %update);
}

=item tkt_search (TYPE, SEARCH, EXTRA)

Search for a ticket.

=cut

sub tkt_search {
    my ($self, $type, $search, $extra) = @_;
    if ($extra) { $$search{'__encoded_query'} = $extra }
    my @entries = $self->query($type, $search );
    return @entries;
}


=item tkt_update (CODE, ARGUMENTS)

Update the ticket, incident, or task associated with the string I<CODE>.
Uses B<update()>, with a hash made of I<ARGUMENTS>.

=cut

sub tkt_update {
    my ($self, $code, %args) = @_;
    return $self->update ($self->_tkt_type_by_number($code),
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
        'Group'         => $self->_tkt_assigned_group ($tkt),
        'Name'          => $self->_tkt_assigned_person ($tkt),
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
        push @return, Text::Wrap::wrap('', ' ' x 41, sprintf ("  %-33s  %-s",
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
        push @return, '', '    ' . $self->_journal_text ($journal), '';
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
        'Number'        => $self->_tkt_number  ($tkt),
        'Summary'       => $self->_tkt_summary ($tkt),
        'Status'        => $self->_tkt_status  ($tkt),
        'Submitted'     => $self->_format_date ($self->_date_submit($tkt)),
        'Urgency'       => $self->_tkt_urgency ($tkt),
        'Priority'      => $self->_tkt_priority ($tkt),
        'Service Type'  => $self->_tkt_svctype ($tkt),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item string_requestor (TICKET)

Generates a report describing the requestor of the ticket.

=cut

sub string_requestor {
    my ($self, $tkt) = @_;
    my @return = "Requestor Info";

    my $requestor = $self->user_by_username ($self->_tkt_requestor($tkt));
    my $createdby = $self->user_by_name ($self->_tkt_caller_id($tkt));

    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'       => $$createdby{'name'},
        'Email'      => $$createdby{'email'},
        'Created By' => $$requestor{'name'} || $self->_tkt_opened_by ($tkt),
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
        'Resolved By' => $self->_tkt_resolved_by ($tkt),
        'Date'        => $self->_format_date ($self->_date_resolved($tkt)),
        'Close Code'  => $self->_tkt_resolved_code ($tkt)
    );
    push @return, '', $self->_format_text ({'prefix' => '  '},
        $self->_tkt_resolved_text($tkt));
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

=item summary ( TICKET [, TICKET [, TICKET [...]]] )

Generates a report showing a human-readable summary of a series of tickets,
suitable for presenting in list form.

=cut

sub summary {
    my ($self, @tickets) = @_;
    my @return;

    foreach my $tkt (@tickets) {
        print Dumper($tkt);
        my $cid = $self->_tkt_caller_id ($tkt);
        my $createdby  = $self->user_by_name ($cid);
        unless ($createdby) {
            my $rid = $self->_tkt_requestor($tkt);
            $createdby = $self->user_by_username ($rid) || {};
        }

        my $assignedto = {};
        my $aid = $self->_tkt_assigned_person ($tkt);
        if ($aid ne '(none)') {
            $assignedto = $self->user_by_name ($aid);
        }

        my $inc_num     = _incident_shorten ($self->_tkt_number ($tkt));
        my $request     = $createdby->{'dv_user_name'} || '*unknown*';
        my $assign      = $assignedto->{'dv_user_name'} || '*unassigned*';
        my $group       = $self->_tkt_assigned_group ($tkt);
        my $status      = $self->_tkt_status ($tkt)
                            || $self->_tkt_itil_state ($tkt)
                            || $self->_tkt_stage ($tkt);
        my $created     = $self->_format_date ($self->_date_submit ($tkt));
        my $updated     = $self->_format_date ($self->_date_update ($tkt));
        my $description = $self->_tkt_summary ($tkt);

        push @return, sprintf ("%-12.12s %-15.15s %-15.15s %-17.17s %17.17s",
            $inc_num, $request, $assign, $group, $status );
        push @return, sprintf (" Created: %-20.20s        Updated: %-20.20s",
            $created, $updated);
        push @return, sprintf (" Subject: %-70.70s", $description);
    }
    return wantarray ? @return : join ("\n", @return);
}

=back

=cut

##############################################################################
### User and Group Subroutines ###############################################
##############################################################################

=head2 Users and Groups

=over 4

=item group_by_groupname (I<NAME>)

Return the matching of group entries with name I<NAME> (hopefully just one).

=cut

sub group_by_groupname {
    my ($self, $name) = @_;
    if (defined $GROUPCACHE{$name}) { return $GROUPCACHE{$name} }
    my @groups = $self->query ('sys_user_group', { 'name' => $name });
    return undef unless (scalar @groups == 1);
    $GROUPCACHE{$name} = $groups[0];
    return $GROUPCACHE{$name};
}

=item groups_by_username (I<NAME>)

Return an array of hashrefs, each matching a 'sys_user_group' object
associated with user I<NAME>.

=cut

sub groups_by_username {
    my ($self, $user) = @_;

    my @entries;
    foreach my $entry ($self->query ('sys_user_grmember',
        { 'user' => $user } )) {
        my $id = $$entry{'group'};
        foreach ($self->query ('sys_user_group', { 'sys_id' => $id })) {
            push @entries, $_;
        }
    }
    return @entries;
}

=item users_by_groupname (I<NAME>)

Returns an array of hashrefs, each matching a 'sys_user' object associated
with a user in group I<NAME>.

=cut

sub users_by_groupname {
    my ($self, $name) = @_;
    my @entries;
    foreach my $entry ($self->query ('sys_user_grmember',
        { 'group' => $name })) {
        my $id = $$entry{'user'};
        foreach ($self->query ('sys_user', { 'sys_id' => $id })) {
            push @entries, $_;
        }
    }
    return @entries;
}

=item user_by_name (I<NAME>)

Give the user hashref associated with name I<NAME>.  Returns the first matching
hashref.

=cut

sub user_by_name {
    my ($self, $name) = @_;
    if (defined $NAMECACHE{$name}) { return $NAMECACHE{$name} }
    my @users = $self->query ('sys_user', { 'name' => $name });
    return undef unless (scalar @users == 1);
    $USERCACHE{$name} = $users[0]->result;
    return $USERCACHE{$name};
}

=item user_by_username (I<NAME>)

Give the user hashref associated with username I<NAME>.  Returns the first matching
hashref.

=cut

sub user_by_username {
    my ($self, $username) = @_;
    if (defined $USERCACHE{$username}) { return $USERCACHE{$username} }
    my @users = $self->query ('sys_user', { 'user_name' => $username });
    return undef unless (scalar @users == 1);
    $USERCACHE{$username} = $users[0]->result;
    return $USERCACHE{$username};
}

=item user_in_group (I<USER>, I<GROUP>)

Returns 1 if the given USER is in group GROUP.

=cut

sub user_in_group {
    my ($self, $username, $group) = @_;
    my @users = $self->users_by_groupname ($group);
    foreach (@users) {
        return 1 if $_->{dv_user_name} eq $username;
    }
    return 0;
}

=item user_in_groups (I<USER>)

Return an array of group names of which the user I<NAME> is a member.

=cut

sub user_in_groups {
    my ($self, $user) = @_;
    my @return;
    foreach my $group ($self->groups_by_username ($user)) {
        push @return, $group->{name};
    }
    return @return;
}

=back

=cut

##############################################################################
### SHOULD MOVE TO ::CONFIG
##############################################################################

### set_ack (FIELD, VALUE)
# Set $CONFIG->{ack}->{FIELD} = VALUE

sub set_ack    { set_config ('ack', @_ ) }

### set_config (FIELD, SUBFIELD, VALUE)
# Set $CONFIG->{FIELD}->{SUBFIELD} = VALUE

sub set_config {
    my $config = $_->config_hash;
    $config ->{$_[0]}->{$_[1]} = $_[2]
}

### set_ticket (FIELD, VALUE)
# Set $CONFIG->{ticket}->{FIELD} = VALUE

sub set_ticket { set_config ('ticket', @_ ) }

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
    $inc =~ s/^(INC|RITM|TASK|TKT)0+/$1/;
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
    foreach my $entry ($self->query ('sys_journal_field',
        { 'element_id' => $tkt->{'sys_id'} })) {
        my $key = $self->_journal_date($entry);
        $entries{$key} = $entry;
    }
    foreach (sort keys %entries) { push @return, $entries{$_} }

    return @return;
}

### _tkt_* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash, or a suitable
# default value.  Should be fairly self-explanatory.

sub _tkt_assigned_group  { $_[1]{'dv_assignment_group'}  || '(none)'    }
sub _tkt_assigned_person { $_[1]{'dv_assigned_to'}       || '(none)'    }
sub _tkt_caller_id       { $_[1]{'dv_caller_id'} || $_[1]{'caller_id'} || '' }
sub _date_resolved   { $_[1]{'dv_resolved_at'}       || ''          }
sub _date_submit     { $_[1]{'dv_opened_at'}         || ''          }
sub _date_update     { $_[1]{'dv_sys_updated_on'}    || ''          }
sub _tkt_description     { $_[1]{'description'}          || ''          }
sub _tkt_itil_state      { $_[1]{'u_itil_state'}         || ''          }
sub _tkt_number          { $_[1]{'number'}               || '(none)'    }
sub _tkt_opened_by       { $_[1]{'dv_opened_by'}         || '(unknown)' }
sub _tkt_priority        { $_[1]{'dv_priority'}          || '(unknown)' }
sub _tkt_requestor       { $_[1]{'dv_sys_created_by'}    || '(unknown)' }
sub _tkt_resolved_by     { $_[1]{'dv_resolved_by'}       || '(none)'    }
sub _tkt_resolved_code   { $_[1]{'close_code'}           || '(none)'    }
sub _tkt_resolved_text   { $_[1]{'close_notes'}          || '(none)'    }
sub _tkt_sys_created_by  { $_[1]{'dv_sys_created_by'}    || '(none)'    }
sub _tkt_stage           { $_[1]{'stage'}                || ''          }
sub _tkt_state           { $_[1]{'incident_state'}       || 0           }
sub _tkt_status          { $_[1]{'dv_incident_state'}    || '' }
sub _tkt_summary         { $_[1]{'dv_short_description'} || '(none)'    }
sub _tkt_svctype         { $_[1]{'u_service_type'}       || '(unknown)' }
sub _tkt_urgency         { $_[1]{'dv_urgency'}           || '(unknown)' }

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
