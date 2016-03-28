package FNAL::SNOW;
our $VERSION = "1.03";

=head1 NAME

FNAL::SNOW - working with the FNAL Service Now implementation

=head1 SYNOPSIS

  use FNAL::SNOW;

  my $snow = FNAL::SNOW->init ();
  my $config = $SNOW->config_hash;
  $snow->connect;

  [...]

=head1 DESCRIPTION

FNAL::SNOW provides an interface to the Service Now service run at the Fermi
National Accelerator Laboratory.  It is primarily useful for loading and
manipulating help desk objects (e.g. Incidents).

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
use Data::Dumper;
use Date::Manip;
use FNAL::SNOW::Config;
use MIME::Lite;
use POSIX qw/strftime/;
use ServiceNow;
use ServiceNow::Configuration;
use Text::Wrap;

struct 'FNAL::SNOW' => {
    'config'      => '$',
    'config_file' => '$',
    'debug'       => '$',
    'sn'          => '$',
    'snconf'      => '$',
};

use vars qw/%GROUPCACHE %USERCACHE %NAMECACHE/;

##############################################################################
### Initialization Subroutines ###############################################
##############################################################################

=head1 FUNCTIONS

=head2 Initializion

These functions are used for creating the underlying objects.

=over 4

=item config_hash ()

Returns the configuration data as a hash.

=cut

sub config_hash { return shift->config->config }

=item connect ()

Connects to Service Now given the information in the FNAL::SNOW::Config: $
associated with 'servicenow'.

=cut

sub connect {
    my ($self) = @_;
    my $conf = $self->config_hash;
    return $self->sn if $self->sn;

    unless (my $snconf = $self->snconf) {
        $snconf ||= ServiceNow::Configuration->new ();
        $snconf->setSoapEndPoint ($conf->{servicenow}->{url});
        $snconf->setUserName     ($conf->{servicenow}->{username});
        $snconf->setUserPassword ($conf->{servicenow}->{password});
        $self->snconf ($snconf);
    }
    my $SN = ServiceNow->new ($self->snconf);
    $self->sn ($SN);
    return $SN;
}

=item init (ARGHASH)

Initializes the FNAL::SNOW object.  This includes setting up the
FNAL::SNOW::Config object with load_yaml ().  Returns the new FNAL::SNOW
object.

=cut

sub init {
    my ($self, %args) = @_;
    my $obj = $self->new (%args);
    my $config = $obj->load_yaml ($obj->config_file);
    $obj->config ($config);
    return $obj;
}

=item load_yaml I<FILE>

Uses FNAL::SNOW::Config to load a YAML configuration file and create a
configuration object.  Dies if we can't open the file for some reason.
Returns the configuration object, and stores the FNAL::SNOW::Config object in
F<config>.

=cut

sub load_yaml {
    my ($self, $file) = @_;
    my $config = FNAL::SNOW::Config->load_yaml ($file);
    $self->config ($config);
    return $config;
}

=back

=cut

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
entries.

=cut

sub read { query(@_) }

sub query {
    my ($self, $table, $params) = @_;
    my $glide = ServiceNow::GlideRecord->new ($self->snconf, $table);
    $glide->query ($params);

    my @return;
    while ($glide->next()) {
        my %record = $glide->getRecord();
        push @return, \%record;
    }
    return @return;
}

=item update (TABLE, QUERY, UPDATE)

Updates Service Now objects in table I<TABLE> matching parameters from the
hashref I<QUERY>.  I<UPDATE> is a hashref containing updates.  Returns an
array of updated entries.

=cut

sub update {
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

##############################################################################
### Ticket Subroutines #######################################################
##############################################################################

=head2 Tickets

These subroutines manipulate Incidents.  (They should probably be moved off to
a separate class).

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
    if ($self->debug) {
        print "  search criteria:\n";
        foreach my $key (sort keys %{$search}) { 
            print "    $key: $$search{$key}\n";
        }
        print "  type: $type\n";
    }
    my @entries = $self->query($type, $search);
    return @entries;
}

sub incident_list { shift->tkt_list_by_type ('Incident', @_) }

=item tkt_list_by_assignee (I<TYPE>, I<EXTRA>)

Queries for incidents assigned to the user I<NAME>.  Returns an array of
matching entries.

=cut

sub tkt_list_by_assignee {
    my ($self, $type, $user, $extra) = @_;
    $self->tkt_list_by_type ( $type, { 'assigned_to' => $user }, $extra )
}

sub incident_list_by_assignee { shift->tkt_list_by_assignee ('Incident', @_) }

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

=back

=cut

##############################################################################
### Incident Lists ###########################################################
##############################################################################

=head2 Ticket List Text Functions

These functions generate an array of ticket objects, and pass them through
B<tkt_list()> to generate human-readable reports.  Each of them either returns
an array of lines suitable for printing, or (in a scalar syntax) a single
string with built-in newlines.

=over 4

=item text_tktlist_assignee (TYPE, USER, SUBTYPE)

List incidents assigned to user I<USER>.  I<SUBTYPE> can be used to filter
based on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_assignee {
    my ($self, $type, $user, $subtype) = @_;
    my $t = $self->_tkt_type ($type);
    my ($extra, $text) = _tkt_filter ($type, 'subtype' => $subtype);
    $text = "== $text assigned to user '$user'";

    return $self->tkt_list ($text,
        $self->tkt_list_by_assignee ($t, $user, $extra)
    );
}

sub text_inclist_assignee { shift->text_tktlist_assignee ('Incident', @_); }

=item text_tktlist_group (TYPE, GROUP, SUBTYPE)

List incidents assigned to group I<GROUP>.  I<SUBTYPE> can be used to filter
based on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_group {
    my ($self, $type, $group, $subtype) = @_;
    my $t = $self->_tkt_type ($type);
    my ($extra, $text) = _tkt_filter ($type, 'subtype' => $subtype);
    $text = "== $text assigned to group '$group'";
    return $self->tkt_list ( $text,
        $self->tkt_list_by_type ($t, { 'assignment_group' => $group }, $extra)
    );
}

sub text_inclist_group { shift->text_tktlist_group ('Incident', @_); }

=item text_tktlist_submit (TYPE, USER, SUBTYPE)

List tickets submitted by user I<USER>.  I<SUBTYPE> can be used to filter based
on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_submit {
    my ($self, $type, $user, $subtype) = @_;
    my $t = $self->_tkt_type ($type);
    my ($extra, $text) = _tkt_filter ($type, 'subtype' => $subtype);
    $text = "== $text submitted by user '$user'";
    return $self->tkt_list ( $text,
        $self->tkt_list_by_type ($t, { 'sys_created_by' => $user }, $extra)
    );
}

sub text_inclist_submit { shift->text_tktlist_group ('Incident', @_) }

=item text_tktlist_unassigned (TYPE, GROUP)

List unresolved, unassigned tickets assigned to group I<GROUP>.

=cut

sub text_tktlist_unassigned {
    my ($self, $type, $group) = @_;
    my $t = $self->_tkt_type ($type);
    my ($extra, $text) = _tkt_filter ($type,
        'unassigned' => 1, 'subtype' => 'unresolved');
    $text = "== $group: $text";
    return $self->tkt_list ( $text,
        $self->tkt_list_by_type($t, { 'assignment_group' => $group }, $extra)
    );
}

sub text_inclist_unassigned { shift->text_tktlist_unassigned ('Incident', @_) }

=item text_tktlist_unresolved (TYPE, GROUP, TIMESTAMP)

List unresolved tickets assigned to group I<GROUP> that were submitted before
the timestamp I<TIMESTAMP>.

=cut

sub text_tktlist_unresolved {
    my ($self, $type, $group, $timestamp) = @_;
    my $t = $self->_tkt_type ($type);
    my ($extra, $text) = _tkt_filter ($type,
        'submit_before' => $timestamp, 'subtype' => 'unresolved');
    $text = "== $group: $text";
    return $self->tkt_list ( $text,
        $self->tkt_list_by_type ($t, { 'assignment_group' => $group }, $extra)
    );
}

sub text_inclist_unresolved { shift->text_tktlist_unresolved ('Incident', @_) }

=back

=cut

##############################################################################
### Generic Ticket Actions ###################################################
##############################################################################

=head2 Generic Ticket Actions

These should ideally work against incidents, tasks, requests, etc.

=over 4

=item tkt_by_number

Queries for the ticket I<NUMBER> (after passing that field through
B<parse_ticket_number()> for consistency and to figure out what kind of ticket
we're looking at).  Returns an array of matching entries.

=cut

sub tkt_by_number {
    my ($self, $number) = @_;
    my $num = $self->parse_ticket_number ($number);
    my $type = $self->_tkt_type_by_number ($num);
    return $self->tkt_search ($type, { 'number' => $num });
}

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

Update the ticket to set the state back to 'Work In Progress',
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

=item tkt_string_assignee (TKT)

Generates a report of the assignee information.

=cut

sub tkt_string_assignee {
    my ($self, $tkt) = @_;
    my @return = "Assignee Info";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Group'         => $self->_tkt_assigned_group ($tkt),
        'Name'          => $self->_tkt_assigned_person ($tkt),
        'Last Modified' => $self->_format_date ($self->_tkt_date_update($tkt))
    );
    return wantarray ? @return : join ("\n", @return, '');
}


=item tkt_string_base (TICKET)

Generates a combined report, with the primary, requestor, assignee,
description, journal (if present), and resolution status (if present).

=cut

sub tkt_string_base {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->tkt_string_primary     ($tkt);
    push @return, '', $self->tkt_string_requestor   ($tkt);
    push @return, '', $self->tkt_string_assignee    ($tkt);
    push @return, '', $self->tkt_string_description ($tkt);
    if (my @journal = $self->tkt_string_journal ($tkt)) {
        push @return, '', @journal;
    }
    if ($self->tkt_is_resolved ($tkt)) {
        push @return, '', $self->tkt_string_resolution ($tkt);
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_string_debug (TICKET)

Generates a report showing the content of every field (empty or not).

=cut

sub tkt_string_debug {
    my ($self, $tkt) = @_;
    my @return;
    push @return, "== " . $$tkt{'sys_id'};
    foreach my $key (sort keys %$tkt) {
        push @return, wrap('', ' ' x 41, sprintf ("  %-33s  %-s",
            $key, $$tkt{$key} || '(empty)'));
    }
    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_string_description (TICKET)

Generates a report showing the user-provided description.

=cut

sub tkt_string_description {
    my ($self, $tkt) = @_;
    my @return = "User-Provided Description";
    push @return, $self->_format_text ({'prefix' => '  '},
            $self->_tkt_description ($tkt));
    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_string_journal (TICKET)

Generates a report showing all journal entries associated with this ticket, in
reverse order (blog style).

=cut

sub tkt_string_journal {
    my ($self, $tkt) = @_;
    my @return = "Journal Entries";
    my @entries = $self->_journal_entries ($tkt);
    if (scalar @entries < 1) { return '' }

    my $count = scalar @entries;
    foreach my $journal (reverse @entries) {
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


=item tkt_string_primary (TICKET)

Generates a report on the "primary" information for a ticket - number, text
summary, status, submitted date, urgency, priority, and service type.

=cut

sub tkt_string_primary {
    my ($self, $tkt) = @_;
    my @return = "Primary Ticket Information";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Number'        => $self->_tkt_number  ($tkt),
        'Summary'       => $self->_tkt_summary ($tkt),
        'Status'        => $self->_tkt_status  ($tkt),
        'Submitted'     => $self->_format_date ($self->_tkt_date_submit($tkt)),
        'Urgency'       => $self->_tkt_urgency ($tkt),
        'Priority'      => $self->_tkt_priority ($tkt),
        'Service Type'  => $self->_tkt_svctype ($tkt),
    );
    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_string_requestor (TICKET)

Generates a report describing the requestor of the ticket.

=cut

sub tkt_string_requestor {
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

=item tkt_string_resolution (TICKET)

Generates a report showing the resolution status.

=cut

sub tkt_string_resolution {
    my ($self, $tkt) = @_;
    my @return = "Resolution";
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Resolved By' => $self->_tkt_resolved_by ($tkt),
        'Date'        => $self->_format_date ($self->_tkt_date_resolved($tkt)),
        'Close Code'  => $self->_tkt_resolved_code ($tkt)
    );
    push @return, '', $self->_format_text ({'prefix' => '  '},
        $self->_tkt_resolved_text($tkt));
    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_string_short (TICKET)

Like tkt_string_basic(), but dropping the worklog.

=cut

sub tkt_string_short {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->tkt_string_primary     ($tkt);
    push @return, '', $self->tkt_string_requestor   ($tkt);
    push @return, '', $self->tkt_string_assignee    ($tkt);
    push @return, '', $self->tkt_string_description ($tkt);
    if ($self->tkt_is_resolved ($tkt)) {
        push @return, '', $self->tkt_string_resolution ($tkt);
    }

    return wantarray ? @return : join ("\n", @return, '');
}

=item tkt_summary ( TICKET [, TICKET [, TICKET [...]]] )

Generates a report showing a human-readable summary of a series of tickets,
suitable for presenting in list form.

=cut

sub tkt_summary {
    my ($self, @tickets) = @_;
    my @return;

    foreach my $tkt (@tickets) {
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
        my $created     = $self->_format_date ($self->_tkt_date_submit ($tkt));
        my $updated     = $self->_format_date ($self->_tkt_date_update ($tkt));
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
    print "user_by_name: $name\n" if $self->debug;
    if (defined $NAMECACHE{$name}) { return $NAMECACHE{$name} }
    my @users = $self->query ('sys_user', { 'name' => $name });
    return undef unless (scalar @users == 1);
    $NAMECACHE{$name} = $users[0];
    return $NAMECACHE{$name};
}


=item user_by_username (I<NAME>)

Give the user hashref associated with username I<NAME>.  Returns the first matching
hashref.

=cut

sub user_by_username {
    my ($self, $username) = @_;
    print "user_by_username: $username\n" if $self->debug;
    if (defined $USERCACHE{$username}) { return $USERCACHE{$username} }
    my @users = $self->query ('sys_user', { 'user_name' => $username });
    return undef unless (scalar @users == 1);
    $USERCACHE{$username} = $users[0];
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
sub _tkt_date_resolved   { $_[1]{'dv_resolved_at'}       || ''          }
sub _tkt_date_submit     { $_[1]{'dv_opened_at'}         || ''          }
sub _tkt_date_update     { $_[1]{'dv_sys_updated_on'}    || ''          }
sub _tkt_description     { $_[1]{'description'}          || ''          }
sub _tkt_itil_state      { $_[1]{'u_itil_state'}         || ''          }
sub _tkt_number          { $_[1]{'number'}               || '(none)'    }
sub _tkt_opened_by       { $_[1]{'dv_opened_by'}         || '(unknown)' }
sub _tkt_priority        { $_[1]{'dv_priority'}          || '(unknown)' }
sub _tkt_requestor       { $_[1]{'dv_sys_created_by'}    || '(unknown)' }
sub _tkt_resolved_by     { $_[1]{'dv_resolved_by'}       || '(none)'    }
sub _tkt_resolved_code   { $_[1]{'close_code'}           || '(none)'    }
sub _tkt_resolved_text   { $_[1]{'close_notes'}          || '(none)'    }
sub _tkt_stage           { $_[1]{'stage'}                || ''          }
sub _tkt_state           { $_[1]{'incident_state'}       || 0           }
sub _tkt_status          { $_[1]{'dv_incident_state'}    || '' }
sub _tkt_summary         { $_[1]{'dv_short_description'} || '(none)'    }
sub _tkt_svctype         { $_[1]{'u_service_type'}       || '(unknown)' }
sub _tkt_urgency         { $_[1]{'dv_urgency'}           || '(unknown)' }

### _tkt_filter (TYPE, ARGHASH)
# Generates the text and "__encoded_query" search terms associated with ticket
# searches.  We currently support:
#
#    submit_before  (INT)       opened_at < YYYY-MM-DD HH:MM:SS
#    subtype        open        incident_state < 4
#                   closed      incident_state >= 4
#                   unresolved  incident_state < 6
#                   other       (no filter)
#    unassigned     (true)      assigned_to=NULL
#
# Returns two strings the EXTRA query and the TEXT associated with the search.

sub _tkt_filter {
    my ($type, %args) = @_;
    my ($text, $extra);

    my ($t) = _tkt_type(undef, $type);

    my $subtype = $args{'subtype'} || '';
    my $unassigned = $args{'unassigned'} || 0;

    my $submit_before = $args{'submit_before'} || '';

    my @extra;
    if      (lc $subtype eq 'open') {
        $text  = "Open ${type}s";
        push @extra, "incident_state<4";
        push @extra, "stage!=complete";
        push @extra, "stage!=Request Cancelled";
    } elsif (lc $subtype eq 'closed') {
        $text = "Closed ${type}s";
        push @extra, 'incident_state>=4';
        push @extra, "stage=Request Cancelled";
    } elsif (lc $subtype eq 'unresolved') {
        $text = "Unresolved ${type}s";
        push @extra, 'incident_state<6';
        push @extra, "stage!=complete";
    } elsif (defined ($subtype)) {
        $text = "All ${type}s"
    }

    if ($unassigned) {
        $text = "Unassigned $text";
        push @extra, 'assigned_to=NULL';
    }

    if ($submit_before) {
        my $time = strftime ("%Y-%m-%d %H:%M:%S %Z", localtime ($submit_before));
        push @extra, "opened_at<$time";
        $text  = "$text submitted before $time";
    }
    return (join ('^', @extra), $text);
}

### _tkt_type (SELF, NAME)
# Returns the associated table name for the given NAME.
sub _tkt_type {
    my ($self, $name) = @_;
    if ($name =~ /^inc/i)  { return 'incident'    }
    if ($name =~ /^req/i)  { return 'sc_request'  }
    if ($name =~ /^ritm/i) { return 'sc_req_item' }
    if ($name =~ /^tas/i)  { return 'sc_task'     }
    return $name;
}

### _tkt_type_by_number (SELF, NUMBER)
# Returns the associated table name for the given NUMBER style.
sub _tkt_type_by_number {
    my ($self, $number) = @_;
    if ($number =~ /^INC/)  { return 'incident'    }
    if ($number =~ /^REQ/)  { return 'sc_request'  }
    if ($number =~ /^RITM/) { return 'sc_req_item' }
    if ($number =~ /^TASK/) { return 'sc_task'     }
    return;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<ServiceNow>

=head1 SEE ALSO

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014-2016, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
