INCIDENT?= 'INC520944'
RITM?= 'RITM0208206'
REQ?= 'REQ000000229964'

#########################################################################
### Incidents / Tickets #################################################
#########################################################################

ticket-new:
	@echo "Testing" | ../usr/bin/snow-ticket-create --subject testing \
		--group ECF-CIS --ticket new-cis-ticket.yaml

ticket-list:
	@ ../usr/bin/snow-ticket-list -g ECF-CIS

ticket:
	@ ../usr/bin/snow-ticket $(INCIDENT)

ticket-journal:
	@ ../usr/bin/snow-ticket-journal $(INCIDENT) 'testing again'

ticket-assign:
	@ ../usr/bin/snow-ticket-assign $(INCIDENT) -u tskirvin -g ECF-CIS

ticket-unassign:
	@ ../usr/bin/snow-ticket-unassign $(INCIDENT)

ticket-resolve:
	@ ../usr/bin/snow-ticket-resolve $(INCIDENT) 'testing'

ticket-reopen:
	@ ../usr/bin/snow-ticket-reopen $(INCIDENT)

ticket-all: ticket-new ticket-list ticket ticket-journal ticket-assign ticket-unassign ticket-resolve ticket-reopen

#########################################################################
### RITMs ###############################################################
#########################################################################

ritm-new:
	@echo "Testing" | ../usr/bin/snow-ticket-create --subject testing \
		--type ritm --group ECF-CIS --ticket new-cis-ritm.yaml --debug

ritm-list: ritm-list-group

ritm-list-assign:
	@ ../usr/bin/snow-ticket-list --group ECF-CIS --type ritm \
		--query assign --user tskirvin 

ritm-list-group:
	@ ../usr/bin/snow-ticket-list --group ECF-CIS --type ritm \
		--query group

ritm-list-submit:
	@ ../usr/bin/snow-ticket-list --type ritm \
		--query submit --user tskirvin

ritm-list-unassigned:
	@ ../usr/bin/snow-ticket-list --group ECF-CIS --type ritm \
		--query unassigned

ritm-list-unresolved:
	@ ../usr/bin/snow-ticket-list --group ECF-CIS --type ritm \
		--query unresolved

ritm:
	@ ../usr/bin/snow-ticket $(RITM)

ritm-debug:
	@ ../usr/bin/snow-ticket $(RITM) --type debug

ritm-journal:
	@ ../usr/bin/snow-ticket $(RITM) --type journal --debug

ritm-short:
	@ ../usr/bin/snow-ticket $(RITM) --type short

ritm-add-journal:
	@ ../usr/bin/snow-ticket-journal $(RITM) 'testing again'

ritm-assign:
	@ ../usr/bin/snow-ticket-assign $(RITM) -u tskirvin -g ECF-CIS

ritm-unassign:
	@ ../usr/bin/snow-ticket-unassign $(RITM)

ritm-resolve:
	@ ../usr/bin/snow-ticket-resolve $(RITM) 'testing'

ritm-reopen:
	@ ../usr/bin/snow-ticket-reopen $(RITM)

#########################################################################
### Requests ############################################################
#########################################################################

request-new:
	@echo "Testing" | /usr/bin/snow-ticket-create --subject testing \
		--type request --group ECF-CIS --ticket new-cis-request.yaml --debug
