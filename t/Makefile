INCIDENT?= 'INC00000534135'
RITM?= 'RITM0208206'
REQ?= 'REQ000000229964'

#########################################################################
### Incidents / Tickets #################################################
#########################################################################

incident-new:
	@echo "Testing" | ../usr/bin/snow-incident-create --subject testing \
		--group ECF-CIS --ticket new-cis-ticket.yaml --debug

incident-list:
	@ ../usr/bin/snow-ticket-list -g ECF-CIS --debug

incident:
	@ ../usr/bin/snow-ticket $(INCIDENT) --debug

incident-journal:
	@ ../usr/bin/snow-ticket-journal $(INCIDENT) 'testing again' --debug

incident-assign:
	@ ../usr/bin/snow-ticket-assign $(INCIDENT) -u '' -g ECF-CIS --debug

incident-unassign:
	@ ../usr/bin/snow-ticket-unassign $(INCIDENT) --debug

incident-resolve:
	@ ../usr/bin/snow-ticket-resolve $(INCIDENT) 'testing' --debug

incident-reopen:
	@ ../usr/bin/snow-ticket-reopen $(INCIDENT) --debug

incident-all: ticket-new ticket-list ticket ticket-journal ticket-assign ticket-unassign ticket-resolve ticket-reopen

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
	@ ../usr/bin/snow-ticket $(RITM) --debug

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
	@ ../usr/bin/snow-ticket-reopen $(RITM) --debug

#########################################################################
### Requests ############################################################
#########################################################################

request-new:
	@echo "Testing" | /usr/bin/snow-request-create --subject testing \
		--type request --group ECF-CIS --ticket new-cis-request.yaml --debug
	
request:
	@ ../usr/bin/snow-ticket $(REQ) --debug
