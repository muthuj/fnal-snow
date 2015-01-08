# FNAL::SNOW - a command-line interface to the Fermi Service Now instance

Fermi uses Service Now for its internal ticketing system.  Its primary
interface has historically been the web interface.  This tool provides an
alternative command-line interface which takes advantage of the extensive
web API and associated perl modules provided by the Service Now company.

The primary purpose of this code is to provide tools to search, display, 
and interact with Incidents within the Service now system.  The code also
provides some basic support for other incident types - Tasks, Requests,
and Requested Items.

This code should be generically useful to any Linux-y group at FNAL.  The
only required configuration is a single YAML config file listing a
username, password, and url for the Service Now instance.

# How To Use

## Command Line Interface

All of the command-line tools have both '--help' and '--man'
functionality, as well as installed manual pages ('man snow-ticket-list').

### snow-ticket-list

    cmsadmin1 ~% snow-ticket-list --query group
    == Open incidents assigned to group 'CMS-Tier1-LPC'

    INC425894  cd-srv-goc-ops   Richard Thompson   CMS-Tier1-LPC     Work in Progre
     Created: 2014-07-16 16:35:11     Updated: 2014-07-18 18:02:15
     Subject: T2_US_Purdue: 20 Gbps test from T1_US_FNAL

    INC426535  cd-srv-goc-ops   Catalin Dumitresc  CMS-Tier1-LPC     Work in Progre
     Created: 2014-07-18 16:18:11     Updated: 2014-07-18 17:58:16
     Subject: Upgrade pileup datasets needing replication at FNAL

    [...]

This tool is used to print ticket summaries based on a variety of queries.  
The supported top-level queries are:

* assign - show tickets assigned to a specified user.
* group - show tickets assigned to a specified group, or all groups
    associated with a specified user.  
* submit - show tickets submitted by a specified user.
* unassigned - show tickets assigned to a specified group that have not 
    been assigned to an individual.
* unresolved - show tickets assigned to a specified group that have not
    been resolved, and which were submitted before a specified date.

Most query types also support further filtering based on a subquery:

* closed - only show closed tickets
* open - only show open tickets (default)
* unresolved - only show unresolved tickets

Some useful queries:

    snow-ticket-list --help
    snow-ticket-list --query assign
    snow-ticket-list --query group  --user `whoami`
    snow-ticket-list --query submit --user `whoami` --subquery closed
    snow-ticket-list --query unassigned --group ECF-CIS
    snow-ticket-list --query unresolved --group all --user tskirvin

### snow-ticket

    cmsadmin1 ~% snow-ticket INC425894
    Primary Ticket Information
      Number:              INC000000425894
      Summary:             T2_US_Purdue: 20 Gbps test from T1_US_FNAL
      Status:              Work in Progress
      Submitted:           2014-07-16 16:35:11 CDT
      Urgency:             3 - Medium
      Priority:            3 - Medium
      Service Type:        User Service Restoration
      ITIL Status:         *unknown*
    
    Requestor Info
      Name:                cd-srv-goc-ops
    
    Assignee Info
      Group:               CMS-Tier1-LPC
      Name:                Richard Thompson
      Last Modified:       2014-07-18 18:02:15 CDT
    
    User-Provided Description
      Hello,
         Could somebody schedule the Phedex load test from T1_US_FNAL  to
      [...]

    Journal Entries
      Entry 20
        Date:                2014-07-18 18:02:15 CDT
        Created By:          cd-srv-goc-ops
        Type:                comments

      [...]

This script prints relevant information about a given ticket, including
basic ticket data; requester information; assignee information; the
description provided by the user; any associated journal entries; and, if
present, the resolution information and text.  It is formatted for ~80
columns.

### snow-ticket-assign

This script assigns a ticket to a specified user or group.  

### snow-ticket-journal

This script creates a new journal entry for a specified incident.  This
can be used for internal notes (default) or for user communication with
`--type comment` (though email is generally the better solution for the
latter).

### snow-ticket-resolve

This script resolves an incident with the specified text.  The resolution
code can be set, but defaults to 'Other'.

### snow-ticket-reopen

This script re-opens an incident.  This doesn't come up very often.

## API

'man FNAL::SNOW' will tell you a fair bit about the functionality of the
API.  Most of the code is dedicated to reporting functions associated with
the command line tools, but the underlying system is flexible enough for 
significant additions.

-------------------------------------------------------------------------------

# Installation

## From RPM

FNAL::SNOW is distributed as an RPM.  We'll put it somewhere soon.

## From Source

Right now, the code is at:

    git@cmssrv96:fnal-snow

This isn't acceptable for public consumption, of course.  We'll improve
this too.

## Configuration

Regardless of which system you use, you will have to create a
configuration file to actually connect to the Service Now instance.  This
file should be named `/etc/snow/config.yaml`, and looks like this:

    servicenow:
        username: 'XXXXXXXX'
        url:      'https://fermi.service-now.com/'
        password: 'XXXXXXXXXXXXXXXX'

If you want to point at the dev instance (useful for testing and development),
point at `https://fermidev.service-now.com/` instead.

### Getting a User ID

In short: file a ticket and ask for a new Service Now static user.  You'll
have to figure out a name that's mutually acceptable.  I don't really have
any strong suggestions here, except to note that this may take a while,
and that it's more complicated than I expected.  (This may improve over
time if multiple sites use this tool.)
