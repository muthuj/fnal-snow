INCIDENT?= 'INC520944'

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


ritm-new:
	@echo "Testing" | ../usr/bin/snow-ticket-create --subject testing \
		--type ritm --group ECF-CIS --ticket new-cis-ritm.yaml --debug

ritm-list:
	@ ../usr/bin/snow-ticket-list --group ECF-CIS --type ritm
