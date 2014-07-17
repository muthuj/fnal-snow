#!/bin/bash -ex
## Test Suite for creating new incidents

##############################################################################
### Configuration ############################################################
##############################################################################

. `pwd`/config.sh

##############################################################################
### main () ##################################################################
##############################################################################

echo_and_do echo "testing" 

echo_and_do echo "(sample)" | nagios-to-snow --type PROBLEM \
    --ciname testing --state DOWN \
    --subject "fake alert: problem with fake host testing" \
    --omdsite testing --debug

! echo_and_do echo "(sample)" | nagios-to-snow --type PROBLEM \
    --ciname testing --state DOWN \
    --subject "fake alert: problem with fake host testing" \
    --omdsite testing --debug

echo_and_do "echo hi there"
