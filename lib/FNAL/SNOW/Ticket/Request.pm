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

See B<FNAL::SNOW::Ticket> for most functions.

=over 4

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
