package FNAL::SNOW::Config;

=head1 NAME

FNAL::SNOW::Config - [...]

=head1 SYNOPSIS

  use FNAL::SNOW::Config;

  my $config = FNAL::SNOW::Config->load_yaml ($filename);

=head1 DESCRIPTION

FNAL::SNOW's configuration is based on a YAML configuration file.  This module
is in charge of loading and presenting that data.  We also provide some helper
functions for using the data in this configuration file.

=cut

##############################################################################
### Configuration ############################################################
##############################################################################

our $CONFIG_FILE = '/etc/snow/config.yaml';

##############################################################################
### Declarations #############################################################
##############################################################################

use strict;
use warnings;

use Class::Struct;
use YAML::Syck;

struct 'FNAL::SNOW::Config' => {
    'config' => '$',
    'file'   => '$'
};

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item load_yaml I<FILE>

Generate a configuration file object from a YAML file.  Dies if we can't open
the file for some reason.

=cut

sub load_yaml {
    my ($self, $file) = @_;
    $file ||= $CONFIG_FILE;
    unless (ref $self) { $self = $self->new ('file' => $file) }
    my $yaml = YAML::Syck::LoadFile ($file);
    unless ($yaml) { die "could not open $file: $@\n" }
    $self->config($yaml);
    return $self;
}

=item nagios_url (HOST, SVC)

Returns a URL pointing at given host/service pair based on the contents of the
F<nagios> configuration section.

=cut

sub nagios_url {
    my ($self, $host, $svc) = @_;
    unless ($self->config) { $self->load_yaml }
    my $config = $self->load_yaml ($CONFIG_FILE);
    my $urlbase = $config->config->{nagios}->{url};
    my $site    = $config->config->{nagios}->{site};

    if (lc $config->config->{nagios}->{style} eq 'check_mk') {
        return $svc ? _nagios_url_cmk_svc  ($urlbase, $site, $host, $svc)
                    : _nagios_url_cmk_host ($urlbase, $site, $host);
    } else {
        return $svc ? _nagios_url_extinfo_svc  ($urlbase, $site, $host, $svc)
                    : _nagios_url_extinfo_host ($urlbase, $site, $host);
    }
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _nagios_url_extinfo_host {
    my ($base_url, $omd_site, $host) = @_;
    return join ('/', $base_url, "cgi-bin", "extinfo.cgi?type=1&host=${host}")
}

sub _nagios_url_extinfo_svc {
    my ($base_url, $omd_site, $host, $svc) = @_;
    return join ('/', $base_url, "cgi-bin",
        "extinfo.cgi?type=2&host=${host}&service=${svc}");
}

sub _nagios_url_cmk_host {
    my ($base_url, $omd_site, $host) = @_;
    return join ('/', $base_url, $omd_site, "check_mk",
        "index.py?start_url=view.py?view_name=hoststatus&site=&host=${host}");
}

sub _nagios_url_cmk_svc {
    my ($base_url, $omd_site, $host, $svc) = @_;
    return join ('/', $base_url, $omd_site, "check_mk",
        "index.py?start_url=view.py?view_name=service&host=${host}&service=${svc}");
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 CONTENTS

[WRITE WHEN WE'RE DONE]

=over 4

=item nagios_ack

=over 2

=item author

=item comment

=back

=item nagios

=over 2

=item url

=item type

=item prefix

=back

=item servicenow

Information necessary to connect to ServiceNow.  This consists of three
strings:

=over 2

=item username

=item url

Should end with a trailing '/'.

=item password

=back

=head1 REQUIREMENTS

B<YAML::Syck>

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
