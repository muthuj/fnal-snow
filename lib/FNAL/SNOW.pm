package FNAL::SNOW;

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

These subroutines are used for direct database queries.

=over 4

=item query (TABLE, PARAMS)

Queries the Service Now database, looking specifically at table I<TABLE> with
parameters stored in the hashref I<PARAMS>.  Returns an array of matching
entries.

=cut

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

=cut

##############################################################################
### Incident Subroutines #####################################################
##############################################################################

=head2 Incidents

These subroutines manipulate Incidents.  (They should probably be moved off to
a separate class).

=over 4

=item incident_list (I<SEARCH>, I<EXTRA>)

Performs an Incident query, and returns an array of matching Incident hashrefs.
This query is against the table F<incident>, using the parameters in the
hashref I<SEARCH> and (if present) the extra parameters in I<EXTRA> against 
the F<__encoded_query> field.  (The last part must be pre-formatted; use this 
at your own risk!)

=cut

sub incident_list {
    my ($self, $search, $extra) = @_;
    if ($extra) { $$search{'__encoded_query'} = $extra }
    my @entries = $self->query( 'incident', $search );
    return @entries;
}

=item incident_list_by_assignee (I<USER>, I<EXTRA>)

Queries for incidents assigned to the user I<NAME>.  Returns an array of
matching entries.

=cut

sub incident_list_by_assignee {
    shift->incident_list ( { 'assigned_to' => shift }, shift )
}

=item incident_by_number (I<NUMBER>)

Queries for the incident I<NUMBER> (after passing that field through
B<parse_incident_number()> for consistency).  Returns an array of matching
entries.

=cut

sub incident_by_number {
    my ($self, $number) = @_;
    my $num = $self->parse_incident_number ($number);
    return $self->incident_list ({ 'number' => $num });
}

=item incident_list_by_submit (I<NAME>, I<EXTRA>)

Queries for incidents submitted by the user I<NAME>.  Returns an array of
matching entries.

=cut

sub incident_list_by_submit {
    shift->incident_list ( { 'assigned_to' => shift }, shift )
}

=item incident_list_by_username (I<USER>)

Queries for incidents belonging to groups associated with user I<USER>.
Returns an array of matching entries.

=cut

sub incident_list_by_username {
    my ($self, $name) = @_;
    my @groups = $self->groups_by_username ($name);
    my @entries;
    foreach my $group (@groups) {
        my $grpname = $$group{'name'};
        push @entries, $self->query ('incident', {
            'assignment_group' => $grpname
        });
    }
    return @entries;
}

=item parse_incident_number (NUMBER)

Standardizes an incident number into the 15-character string starting with
'INC' (or similar).

=cut

sub parse_incident_number {
    my ($self, $num) = @_;
    return $num if $num && $num =~ /^(HD0|INC|TAS)/ && length ($num) == 15;

    $num ||= "";
    if ($num =~ /^(HD0|TAS|INC)(\d+)$/) {
        $num = $1    . ('0' x (12 - length ($num))) . $2;
    } elsif ($num =~ /^(\d+)/) {
        $num = 'INC' . ('0' x (12 - length ($num))) . $1;
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

=head2 Incident List Text Functions

These functions generate an array of incident objects, and pass them through
B<tkt_list()> to generate human-readable reports.  Each of them either returns
an array of lines suitable for printing, or (in a scalar syntax) a single
string with built-in newlines.

=over 4

=item text_inclist_assignee (USER, SUBTYPE)

Wrapper for B<incident_list_by_assignee()>.  B<SUBTYPE> can be used to filt

=cut

sub text_inclist_assignee {
    my ($self, $user, $subtype) = @_;
    my ($extra, $text) = _tkt_filter ('Incident', 'subtype' => $subtype);
    $text = "== $text assigned to user '$user'";

    return $self->tkt_list ( $text,
        $self->incident_list_by_assignee ($user, $extra)
    );
}

=item text_inclist_group (GROUP, SUBTYPE)


Li
Wrapper for B<incident_list( { 'assignment_group' => GROUP } )>.

=cut

sub text_inclist_group {
    my ($self, $group, $subtype) = @_;
    my ($extra, $text) = _tkt_filter ('Incident', 'subtype' => $subtype);
    $text = "== $text assigned to group '$group'";
    return $self->tkt_list ( $text,
        $self->incident_list( { 'assignment_group' => $group }, $extra)
    );
}

=item text_inclist_submit (USER, SUBTYPE)

=cut

sub text_inclist_submit {
    my ($self, $user, $subtype) = @_;
    my ($extra, $text) = _tkt_filter ('Incident', 'subtype' => $subtype);
    $text = "== $text submitted by user '$user'";
    return $self->tkt_list ( $text,
        $self->incident_list( { 'sys_created_by' => $user }, $extra)
    );
}

=item text_inclist_unassigned (GROUP)

=cut

sub text_inclist_unassigned {
    my ($self, $group) = @_;
    my ($extra, $text) = _tkt_filter ('Incident',
        'unassigned' => 1, 'subtype' => 'unresolved');
    $text = "== $group: $text";
    return $self->tkt_list ( $text,
        $self->incident_list( { 'assignment_group' => $group }, $extra)
    );
}

=item text_inclist_unresolved (GROUP, TIMESTAMP)

=cut

sub text_inclist_unresolved {
    my ($self, $group, $timestamp) = @_;
    my ($extra, $text) = _tkt_filter ('Incident',
        'submit_before' => $timestamp, 'subtype' => 'unresolved');
    $text = "== $group: $text";
    return $self->tkt_list ( $text,
        $self->incident_list( { 'assignment_group' => $group }, $extra)
    );
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

Given a list of ticket objects, pushes them all through B<tkt_summary()> and 
combines the text into a single object.

=cut

sub tkt_list {
    my ($self, $text, @list) = @_;
    my @return;
    push @return, $text, '';
    foreach (@list) { push @return, ($self->tkt_summary ($_), '') }
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
description, worklog (if present), and resolution status (if present).

=cut

sub tkt_string_base {
    my ($self, $tkt) = @_;

    my @return;
    push @return,     $self->tkt_string_primary     ($tkt);
    push @return, '', $self->tkt_string_requestor   ($tkt);
    push @return, '', $self->tkt_string_assignee    ($tkt);
    push @return, '', $self->tkt_string_description ($tkt);
    if (my @worklog = $self->tkt_string_worklog ($tkt)) {
        push @return, '', @worklog;
    }
    if ($self->_tkt_is_resolved ($tkt)) {
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
    push @return, $self->_format_text_field (
        {'minwidth' => 20, 'prefix' => '  '},
        'Name'        => $self->_tkt_requestor ($tkt),
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

=item tkt_summary ( TICKET [, TICKET [, TICKET [...]]] )

Generates a report showing a human-readable summary of a series of tickets,
suitable for presenting in list form.

=cut

sub tkt_summary {
    my ($self, @tickets) = @_;
    my @return;
    foreach my $tkt (@tickets) {
        my $inc_num     = _incident_shorten ($self->_tkt_number ($tkt));
        my $request     = $self->_tkt_requestor ($tkt);
        my $assign      = $self->_tkt_assigned_person ($tkt);
        my $group       = $self->_tkt_assigned_group ($tkt);
        my $status      = $self->_tkt_status ($tkt);
        my $created     = $self->_format_date ($self->_tkt_date_submit ($tkt));
        my $updated     = $self->_format_date ($self->_tkt_date_update ($tkt));
        my $description = $self->_tkt_summary ($tkt);

        push @return, sprintf ("%-7s  %-17.17s  %-17.17s  %-17.17s  %12.12s",
            $inc_num, $request, $assign, $group, $status );
        push @return, sprintf (" Created: %-20.20s    Updated: %-20.20s",
            $created, $updated);
        push @return, sprintf (" Subject: %-70.70s", $description);
    }
    return wantarray ? @return : join ("\n", @return);
}

=item tkt_string_worklog (TICKET)

Generates a report showing all journal entries associated with this ticket, in
reverse order (blog style).

=cut

sub tkt_string_worklog {
    my ($self, $tkt) = @_;
    my @return = "Worklog Entries";
    my @entries = $self->_journal_entries ($tkt);
    if (scalar @entries < 1) { return '' }

    my $count = scalar @entries;
    foreach my $journal (@entries) {
        push @return, "  Entry " . $count--;
        push @return, $self->_format_text_field (
            {'minwidth' => 20, 'prefix' => '    '},
            'Date'       => $self->_format_date(
                                $self->_journal_date ($journal)),
            'Created By' => $self->_journal_author ($journal),
        );
        push @return, '', $self->_format_text ({'prefix' => '    '},
            $self->_journal_text ($journal)), '';
    }
    return wantarray ? @return : join ("\n", @return, '');
}

=back

=cut

##############################################################################
### User and Group Subroutines ###############################################
##############################################################################

=head2 Users and Groups

=over 4

=item groups_by_groupname (I<NAME>)

Return an array of group entries with name I<NAME> (hopefully just one).

=cut

sub groups_by_groupname {
    my ($self, $name) = @_;
    my @entries = $self->query ('sys_user_group', { 'name' => $name });
    return @entries;
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

=item users_by_username (I<NAME>)

Give the user hashref associated with user I<NAME>.  Returns an array of
matching hashrefs (hopefully just one).

=cut

sub users_by_username {
    my ($self, $user) = @_;
    my @entries = $self->query ('sys_user', { 'user_name' => $user });
    return @entries;
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
    my ($self, $time) = @_;
    if ($time =~ /^\d+$/) { }   # all is well
    elsif ($time) { $time = UnixDate ($time, "%s") || time; }
    return $time ? strftime ("%Y-%m-%d %H:%M:%S %Z", localtime ($time))
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
    $inc =~ s/^INC0+//;
    return $inc;
}

### _journal_* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash.

sub _journal_author { $_[1]{'sys_created_by'} || '(unknown)' }
sub _journal_date   { $_[1]{'sys_created_on'} || '(unknown)' }
sub _journal_text   { $_[1]{'value'}          || ''          }

### _journal_entries (SELF, TKT)
# List all journal entries associated with this object.

sub _journal_entries {
    my ($self, $tkt) = @_;
    $self->query ('sys_journal_field', { 'element_id' => $tkt->{'sys_id'} });
}

### _tkt_* (SELF, TKT)
# Returns the appropriate data from a passed-in ticket hash, or a suitable
# default value.  Should be fairly self-explanatory.

sub _tkt_assigned_group  { $_[1]{'dv_assignment_group'}  || '(none)'    }
sub _tkt_assigned_person { $_[1]{'dv_assigned_to'}       || '(none)'    }
sub _tkt_date_resolved   { $_[1]{'dv_resolved_at'}       || ''          }
sub _tkt_date_submit     { $_[1]{'opened_at'}            || ''          }
sub _tkt_date_update     { $_[1]{'sys_updated_on'}       || ''          }
sub _tkt_description     { $_[1]{'description'}          || ''          }
sub _tkt_is_resolved     { _tkt_resolved_by($_[1]) ? 1 : 0 }
sub _tkt_number          { $_[1]{'number'}               || '(none)'    }
sub _tkt_priority        { $_[1]{'dv_priority'}          || '(unknown)' }
sub _tkt_requestor       { $_[1]{'dv_sys_created_by'}    || '(unknown)' }
sub _tkt_resolved_by     { $_[1]{'dv_resolved_by'}       || '(none)'    }
sub _tkt_resolved_code   { $_[1]{'close_code'}           || '(none)'    }
sub _tkt_resolved_text   { $_[1]{'close_notes'}          || '(none)'    }
sub _tkt_status          { $_[1]{'dv_incident_state'}    || '(unknown)' }
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
#                   unresolved  incident_state < 7
#                   other       (no filter)
#    unassigned     (true)      assigned_to=NULL
#
# Returns two strings the EXTRA query and the TEXT associated with the search.

sub _tkt_filter {
    my ($type, %args) = @_;
    my ($text, $extra);

    my $subtype = $args{'subtype'} || '';
    my $unassigned = $args{'unassigned'} || 0;

    my $submit_before = $args{'submit_before'} || '';

    my @extra;
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

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

B<ServiceNow>

=head1 SEE ALSO

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
