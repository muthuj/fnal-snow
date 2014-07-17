package SNOW;

=head1 NAME

SNOW

=head1 SYNOPSIS

=head1 DESCRIPTION

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

use YAML::Syck;

##############################################################################
### Subroutines ##############################################################
##############################################################################

=head1 FUNCTIONS

=over 4

=item config_yaml I<FILE>

Generate a configuration file object from a YAML file.  Dies if we can't open
the file for some reason.

=cut

### config_yaml (FILE)
## Load a configuration object from a YAML source file.
sub config_yaml {
    my ($file) = @_;
    $file ||= $CONFIG_FILE;
    my $yaml = YAML::Syck::LoadFile ($file);
    unless ($yaml) { die "could not open $file: $@\n" }
    return $yaml;
}

=back

=cut

##############################################################################
### Internal Subroutines #####################################################
##############################################################################

sub _shorten_incident {
    my ($inc) = @_;
    $inc =~ s/^INC0+//;
    return $inc;
}

##############################################################################
### Final Documentation ######################################################
##############################################################################

=head1 REQUIREMENTS

=head1 SEE ALSO

=head1 AUTHOR

Tim Skirvin <tskirvin@fnal.gov>

=head1 LICENSE

Copyright 2014, Fermi National Accelerator Laboratory

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut

1;
