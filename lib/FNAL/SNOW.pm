package FNAL::SNOW;
our $VERSION = "1.1.0";

=head1 NAME

FNAL::SNOW - working with the FNAL Service Now implementation

=head1 SYNOPSIS

  use FNAL::SNOW;

  my $snow = FNAL::SNOW->init ();
  my $config = $SNOW->config_hash;
  $snow->connect;

  my $number = 'INC0000xxxxx';
  foreach my $tkt ($snow->tkt_by_number ($number)) {
      print scalar $snow->tkt_string_base ($tkt);
  }

=head1 DESCRIPTION

FNAL::SNOW provides an interface to the Service Now service run at the Fermi
National Accelerator Laboratory.  It is primarily useful for loading and
manipulating help desk objects (e.g. Incidents).

Behind the scenes, this module wraps the main ServiceNow perl libraries and the
B<FNAL::SNOW::Ticket::*> suite of modules and provides context for a number of
user scripts and automation.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

## What kinds of incidents do we support?  Each of these corresponds to a
## specific puppet module.  It's okay to load the same module multiple times
## under different names for user convenience.

our %TICKET_TYPES = (
    'incident'    => 'FNAL::SNOW::Ticket::Incident',
    'request'     => 'FNAL::SNOW::Ticket::Request',
    'ritm'        => 'FNAL::SNOW::Ticket::RITM',
    'sc_req_item' => 'FNAL::SNOW::Ticket::RITM',
    'task'        => 'FNAL::SNOW::Ticket::Task',
    'ticket'      => 'FNAL::SNOW::Ticket::Incident',
);

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use Data::Dumper;
use FNAL::SNOW::Config;
use MIME::Lite;
use ServiceNow;
use ServiceNow::Configuration;

## Load the classes from %TICKET_TYPES, above.
foreach my $tkt (sort keys %TICKET_TYPES) {
    my $class = $TICKET_TYPES{$tkt};
    eval "require $class";
    if ( $@ ) { die $@ }
}

=head1 DATA STRUCTURES

=over 4

=item FNAL::SNOW

Primary and simple data structure, this should be fairly straightforward
compared to normal perl modules.

    'config'      => '$'
    'config_file' => '$'
    'debug'       => '$'
    'sn'          => '$'
    'snconf'      => '$'

=cut

struct 'FNAL::SNOW' => {
    'config'      => '$',
    'config_file' => '$',
    'debug'       => '$',
    'sn'          => '$',
    'snconf'      => '$',
};

=item FNAL::SNOW::QueryResult

The result of queries will be a simple object that stores the actual data
results, as well as the table in which we searched.

    'result' => '$'
    'table'  => '$'

=cut

struct 'FNAL::SNOW::QueryResult' => {
    'result' => '$',
    'table'  => '$'
};

=item %GROUPCACHE, %NAMECACHE, %USERCACHE, %USERIDCACHE

Simple hashes to cache user and group query data.

=cut

use vars qw/%GROUPCACHE %USERCACHE %USERIDCACHE %NAMECACHE/;

=back

=cut

##############################################################################
### Initialization Subroutines ###############################################
##############################################################################

=head1 FUNCTIONS

=head2 Initializion

FNAL::SNOW is a B<Config::Struct> object under the covers.  These functions
supplement the basic getter/setter functionality.

=over 4

=item config_hash ()

Returns the configuration data as a hash.  See B<FNAL::SNOW::Config>.

=cut

sub config_hash { return shift->config->config }

=item connect ()

Connects to Service Now given the information in the B<FNAL::SNOW::Config>;
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

These subroutines perform direct database queries, using
B<ServiceNow::GlideRecord>.

=over 4

=item create (TABLE, PARAMS)

Inserts a new item into the Service Now database in table I<TABLE> and based
on the parameters in the hashref I<PARAMS>.  Returns an array of matching
B<FNAL:SNOW::QueryResult> objects the matching items (as pulled from another
query based on the returned sys_id).

=cut

sub create {
    my ($self, $table, $params) = @_;
    my $glide = ServiceNow::GlideRecord->new ($self->snconf, $table);
    if ($self->debug) {
        print "insert: $table, ", Data::Dumper->new ([$params], ['params'])
                ->Indent(0)->Quotekeys(0)->Dump;
    }
    my $id = $glide->insert ($params);
    if ($id) {
        if ($self->debug) { printf " - created id $id\n" }
        return $self->query ($table, {'sys_id' => $id} );
    } else {
        if ($self->debug) { printf " - failed to create\n" }
        return;
    }

}

=item query (TABLE, PARAMS)

Queries the Service Now database, looking specifically at table I<TABLE> with
parameters stored in the hashref I<PARAMS>.  Returns an array of matching
B<FNAL::SNOW::QueryResult> objects.

=cut

sub query {
    my ($self, $table, $params) = @_;
    my $glide = ServiceNow::GlideRecord->new ($self->snconf, $table);
    if ($self->debug) {
        print "query: $table, ", Data::Dumper->new ([$params], ['params'])
                ->Indent(0)->Quotekeys(0)->Dump;
    }
    $glide->query ($params);

    my @return;
    while ($glide->next()) {
        my %record = $glide->getRecord();
        my $obj = FNAL::SNOW::QueryResult->new (
            'table' => $table, 'result' => \%record );
        push @return, $obj;
    }
    if ($self->debug) { printf " - %d results\n", scalar(@return) }
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
    if ($self->debug) {
        print "update: $table, ", Data::Dumper->new ([$query, $update],
            ['query', 'update'])->Indent(0)->Quotekeys(0)->Dump;
    }
    $glide->query ($query);

    my @return;
    while ($glide->next()) {
        foreach (keys %$update) {
            $glide->setValue ($_, $$update{$_});
        }
        $glide->update();
        my %record = $glide->getRecord();
        my $obj = FNAL::SNOW::QueryResult->new (
            'table' => $table, 'result' => \%record );
        push @return, $obj;
    }
    if ($self->debug) { printf " - %d results\n", scalar(@return) }

    return @return;
}

=back

Note: there is no B<delete()>.

=cut

##############################################################################
### Ticket Queries ###########################################################
##############################################################################

=head2 Tickets Queries

These subroutines query tickets from the SNOW database.  I<TYPE> is
the type of ticket we're looking for - Incident, Task, etc.  We return
B<FNAL::SNOW::QueryResult> objects.

=over 4

=item tkt_list_by_assignee (I<TYPE>, I<EXTRA>)

Queries for incidents assigned to the user I<NAME>.  Returns an array of
matching objects.  Uses B<tkt_list_by_type()>.

=cut

sub tkt_list_by_assignee {
    my ($self, $type, $user, $extra) = @_;
    $self->tkt_list_by_type ( $type, { 'assigned_to' => $user }, $extra )
}

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

=back

=cut

##############################################################################
### Generic Ticket Actions ###################################################
##############################################################################

=head2 Generic Ticket Actions

These should ideally work against incidents, tasks, requests, etc, without
needing any actual reference to a specific ticket.

=over 4

=item tkt_by_number (NUMBER)

Queries for the ticket I<NUMBER> (after passing that field through
B<FNAL::SNOW::Ticket>'s B<parse_ticket_number()> for consistency and to figure
out what kind of ticket we're looking at).  Returns an array of matching
FNAL::SNOW::QueryResult entries.

=cut

sub tkt_by_number {
    my ($self, $number) = @_;
    my $num = FNAL::SNOW::Ticket->parse_ticket_number ($number) || return;
    my $type = $self->_tkt_type_by_number ($num) || return;
    my $obj = $type->new ('connection' => $self);
    return $obj->search ({ 'number' => $num });
}

=item tkt_create (TYPE, TICKETHASH)

Creates a new ticket of type I<TYPE>, and returns the number of the created
ticket (or undef on failure).

=cut

sub tkt_create {
    my ($self, $type, %ticket) = @_;
    my @items = $self->create ($type, \%ticket);
    return undef unless (@items && scalar @items == 1);
    return $items[0]->result->{number};
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

=back

=cut

##############################################################################
### Ticket Manipulation ######################################################
##############################################################################

=head2 Ticket Manipulation

These functions manipulate existing B<FNAL::SNOW::QueryResult> objects, and
wrap the per-ticket-class module equivalent functions.

=over 4

=item tkt_assign (TKT_QR, GROUP, USER)

Assigns ticket I<NUMBER> to a given group and/or user.  If we are given a blank
value for I<USER>, we will clear the assignment field.  Returns an array of
updated B<FNAL::SNOW::QueryResult> objects (hopefully just one!).

=cut

sub tkt_assign {
    my ($self, $tkt, $group, $user) = @_;
    my ($obj, $result) = $self->_tkt ($tkt);
    $obj->assign ($result->{'number'}, $group, $user);
}

=item tkt_compare (TKT_QR1, TKT_QR2)

=cut

sub tkt_compare {
    my ($self, $tkt1, $tkt2) = @_;
    return "invalid ticket: $tkt1" unless $tkt1 && ref $tkt1;
    return "invalid ticket: $tkt2" unless $tkt2 && ref $tkt2;

    my ($obj1, $result1) = $self->_tkt ($tkt1);
    my ($obj2, $result2) = $self->_tkt ($tkt2);

    my $num1 = $result1->{'number'}; my $num2 = $result2->{'number'};
    return undef if ($num1 eq $num2);
    return sprintf ('tickets do not match: %s vs %s', $num1, $num2);
}

=item tkt_is_resolved (TKT_QR)

Returns 1 if the ticket is resolved, 0 otherwise.  If there's an error in
detection, print an error message and return that instead.

=cut

sub tkt_is_resolved {
    my ($self, $tkt) = @_;
    my ($obj, $result) = $self->_tkt ($tkt);
    my $return = $obj->is_resolved ($result);
    if ($return =~ /^\d+$/) { return $return }
    else {
        print "error: $return\n";
        return undef;
    }
}

=item tkt_reopen (TKT_QR)

Attempts to re-open the ticket.  The actual work is ticket-type specific, via
function B<reopen()>.

Returns an array of B<FNAL::SNOW::QueryResult> objects matching the updated
entries.

=cut

sub tkt_reopen {
    my ($self, $tkt) = @_;
    my ($obj, $result) = $self->_tkt ($tkt);
    return $obj->reopen ($result->{number})
}

=item tkt_resolve (TKT_QR, ARGHASH)

Attempts to mark the ticket as status 'Resolved'.  The actual work is
ticket-type specific, via function B<resolve()>.  I<ARGHASH> is passed to
this function as well.

Returns an array of B<FNAL::SNOW::QueryResult> objects matching the updated
entries.

=cut

sub tkt_resolve {
    my ($self, $tkt, %args) = @_;
    my ($obj, $result) = $self->_tkt ($tkt);
    return $obj->resolve ($result->{number}, %args)
}

=item tkt_update (TKT_QR, ARGHASH)

Updates the ticket with the content of I<ARGHASH>.

Returns an array of B<FNAL::SNOW::QueryResult> objects matching the updated
entries.

=cut

sub tkt_update {
    my ($self, $tkt, %args) = @_;
    my ($obj, $result) = $self->_tkt ($tkt);
    return $obj->update ($result->{'number'}, %args);
}

=cut

##############################################################################
### Ticket Lists #############################################################
##############################################################################

=head2 Ticket List Text Functions

These functions generate an array of ticket objects, and pass them through the
per-ticket-type B<list()> function to generate human-readable reports.  Each of
them either returns an array of lines suitable for printing, or (in a scalar
syntax) a single string with built-in newlines.

=over 4

=item text_tktlist_assignee (TYPE, USER, SUBTYPE)

List incidents assigned to user I<USER>.  I<SUBTYPE> can be used to filter
based on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_assignee {
    my ($self, $type, $user, $subtype) = @_;
    my $class = $TICKET_TYPES{$type} || return "invalid type: $type";

    my ($extra, $text) = $class->build_filter ('subtype' => $subtype);
    my $obj = $class->new ('connection' => $self);

    $text = "== $text assigned to user '$user'";
    return $obj->list ($text,
        $self->tkt_list_by_assignee ($class->type, $user, $extra)
    );
}

=item text_tktlist_group (TYPE, GROUP, SUBTYPE)

List incidents assigned to group I<GROUP>.  I<SUBTYPE> can be used to filter
based on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_group {
    my ($self, $type, $group, $subtype) = @_;
    my $class = $TICKET_TYPES{$type} || return "invalid type: $type";

    my ($extra, $text) = $class->build_filter ('subtype' => $subtype);
    my $obj = $class->new ('connection' => $self);

    $text = "== $text assigned to group '$group'";
    return $obj->list ( $text,
        $self->tkt_list_by_type (
            $class->type, { 'assignment_group' => $group }, $extra
        )
    );
}

=item text_tktlist_submit (TYPE, USER, SUBTYPE)

List tickets submitted by user I<USER>.  I<SUBTYPE> can be used to filter based
on 'open', 'closed', or 'unresolved' tickets.

=cut

sub text_tktlist_submit {
    my ($self, $type, $user, $subtype) = @_;
    my $class = $TICKET_TYPES{$type} || return "invalid type: $type";

    my ($extra, $text) = $class->build_filter ('subtype' => $subtype);
    my $obj = $class->new ('connection' => $self);

    $text = "== $text submitted by user '$user'";
    return $obj->list ( $text,
        $self->tkt_list_by_type (
            $class->type, { 'sys_created_by' => $user }, $extra
        )
    );
}

=item text_tktlist_unassigned (TYPE, GROUP)

List unresolved, unassigned tickets assigned to group I<GROUP>.

=cut

sub text_tktlist_unassigned {
    my ($self, $type, $group) = @_;
    my $class = $TICKET_TYPES{$type} || return "invalid type: $type";

    my ($extra, $text) = $class->build_filter (
        'unassigned' => 1, 'subtype' => 'unresolved'
    );
    my $obj = $class->new ('connection' => $self);

    $text = "== $group: $text";
    return $obj->list ( $text,
        $self->tkt_list_by_type(
            $class->type, { 'assignment_group' => $group }, $extra
        )
    );
}

=item text_tktlist_unresolved (TYPE, GROUP, TIMESTAMP)

List unresolved tickets assigned to group I<GROUP> that were submitted before
the timestamp I<TIMESTAMP>.

=cut

sub text_tktlist_unresolved {
    my ($self, $type, $group, $timestamp) = @_;
    my $class = $TICKET_TYPES{$type} || return "invalid type: $type";

    my ($extra, $text) = $class->build_filter (
        'submit_before' => $timestamp, 'subtype' => 'unresolved'
    );
    my $obj = $class->new ('connection' => $self);

    $text = "== $group: $text";
    return $obj->list ( $text,
        $self->tkt_list_by_type (
            $class->type, { 'assignment_group' => $group }, $extra
        )
    );
}

=back

=cut

##############################################################################
### Text-Based Ticket Reporting ##############################################
##############################################################################

=head2 Text-Based Ticket Reporting

These functions take existing B<FNAL::SNOW::QueryResult> objects, wrapping
the per-ticket-class module equivalent functions, to produce text output.

=over 4

=item tkt_string_assignee (TKT_QR)

Generates a report of the assignee information.

=cut

sub tkt_string_assignee {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_assignee ($result)
}

=item tkt_string_base (TKT_QR)

Generates a combined report, with the primary, requestor, assignee,
description, journal (if present), and resolution status (if present).

=cut

sub tkt_string_base {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_base ($result);
}

=item tkt_string_debug (TKT_QR)

Generates a report showing the content of every field (empty or not).

=cut

sub tkt_string_debug {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_debug ($result);
}

=item tkt_string_description (TKT_QR)

Generates a report showing the user-provided description.

=cut

sub tkt_string_description {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_description ($result);
}

=item tkt_string_journal (TKT_QR)

Generates a report showing all journal entries associated with this ticket, in
reverse order (blog style).

=cut

sub tkt_string_journal {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_journal ($result);
}

=item tkt_string_resolution (TICKET)

Generates a report showing the resolution status.

=cut

sub tkt_string_resolution {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_resolution ($result);
}

=item tkt_string_short (TICKET)

Like tkt_string_basic(), but dropping the worklog.

=cut

sub tkt_string_short {
    my ($self, $tkt) = @_;
    my ($obj, $result) = _tkt ($self, $tkt);
    return $obj unless $result;
    return $obj->string_short ($result);
}

=back

=cut

##############################################################################
### User and Group Subroutines ###############################################
##############################################################################

=head2 Users and Groups

Service Now has user and group tables.  We can access them directly here, and
cache the results within a single run.

=over 4

=item group_by_groupname (I<NAME>)

Return the matching of group entries with name I<NAME> (hopefully just one).

=cut

sub group_by_groupname {
    my ($self, $name) = @_;
    if (defined $GROUPCACHE{$name}) { return $GROUPCACHE{$name} }
    my @groups = $self->query ('sys_user_group', { 'name' => $name });
    return undef unless (scalar @groups == 1);
    _populate_groupcache($groups[0]->result);
    return $GROUPCACHE{$name};
}

=item groups_by_username (I<NAME>)

Return an array of hashrefs, each matching a 'sys_user_group' object
associated with user I<NAME>.

=cut

sub groups_by_username {
    my ($self, $user) = @_;

    my @entries;
    foreach my $e ($self->query ('sys_user_grmember',
        { 'user' => $user } )) {
        my $entry = $e->result;
        my $id = $$entry{'group'};
        foreach ($self->query ('sys_user_group', { 'sys_id' => $id })) {
            push @entries, $_->result;
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
    foreach my $e ($self->query ('sys_user_grmember',
        { 'group' => $name })) {
        my $entry = $e->result;
        my $id = $$entry{'user'};
        foreach ($self->query ('sys_user', { 'sys_id' => $id })) {
            push @entries, $_->result;
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
    _populate_usercache ($users[0]->result);
    return $USERCACHE{$name};
}

=item user_by_sysid (I<SYS_ID>)

Give the user hashref associated with id I<SYS_ID>.  Returns the first matching
hashref.

=cut

sub user_by_sysid {
    my ($self, $sysid) = @_;
    if (defined $USERIDCACHE{$sysid}) { return $USERIDCACHE{$sysid} }
    my @users = $self->query ('sys_user', { 'sys_id' => $sysid });
    return undef unless (scalar @users == 1);
    _populate_usercache ($users[0]->result);
    return $USERIDCACHE{$sysid};
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
    _populate_usercache ($users[0]->result);
    return $USERCACHE{$username};
}

=item user_in_group (I<USER>, I<GROUP>)

Returns 1 if the given USER is in group GROUP.

=cut

sub user_in_group {
    my ($self, $username, $group) = @_;
    foreach my $e ($self->query ('sys_user_grmember',
        { 'group' => $group })) {
        my $entry = $e->result;
        my $id = $$entry{'user'};
        foreach ($self->query ('sys_user', { 'sys_id' => $id })) {
            return 1 if $_->result->{dv_user_name} eq $username
        }
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
### Internal Subroutines #####################################################
##############################################################################

### _populate_groupcache (RESULT)
# Populate the contents of %GROUPCACHE
sub _populate_groupcache {
    my ($result) = @_;
    $GROUPCACHE  { $$result{'name'}} = $result;
}

### _populate_usercache (RESULT)
# Populate the contents of %USERCACHE, %USERIDCACHE, %NAMECACHE
sub _populate_usercache {
    my ($result) = @_;
    $USERCACHE  { $$result{'user_name'}} = $result;
    $USERIDCACHE{ $$result{'sys_id'}  }  = $result;
    $NAMECACHE  { $$result{'name'}    }  = $result;
    return $result;
}

### _tkt (SELF, TKT)
# Takes a QueryResult object, and makes sure it's all clean; returns a new
# object based on that result, and a hashref of the data from that result.
# Used as the basis of a bunch of other functions.

sub _tkt {
    my ($self, $tkt) = @_;
    my $result = $tkt->result || return 'could not parse result';
    my $table  = $tkt->table  || return 'could not parse table';
    my $class  = $TICKET_TYPES{$table} || return "invalid table: $table";
    my $obj    = $class->new ('connection' => $self);
    return ($obj, $result);
}

### _tkt_type (SELF, NAME)
# Returns the associated table name for the given NAME.
sub _tkt_type {
    my ($self, $name) = @_;
    my $class = $self->_tkt_type_by_number ($name);
    if ($class) { return $class->type }
    else        { return $name }
}

### _tkt_type_by_number (SELF, NUMBER)
# Returns the associated table name for the given NUMBER style.
sub _tkt_type_by_number {
    my ($self, $number) = @_;
    if ($number =~ /^INC/i)  { return 'FNAL::SNOW::Ticket::Incident' }
    if ($number =~ /^REQ/i)  { return 'FNAL::SNOW::Ticket::Request'  }
    if ($number =~ /^RITM/i) { return 'FNAL::SNOW::Ticket::RITM'     }
    if ($number =~ /^TASK/i) { return 'FNAL::SNOW::Ticket::Task'     }
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

Copyright 2014-2015, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
