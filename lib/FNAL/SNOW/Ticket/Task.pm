package FNAL::SNOW::Ticket::Task;

=head1 NAME

FNAL::SNOW::Ticket::Task - Service Now Tasks

=head1 SYNOPSIS

  use FNAL::SNOW::Ticket::Task;

=head1 DESCRIPTION

Tasks are occasionally used within Service Now.  This library should
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

I<sc_task>, I<task>, I<task>

=cut

sub type        { 'sc_task' }
sub type_pretty { 'task' }
sub type_short  { 'task' }

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
