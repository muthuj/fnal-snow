INCIDENT?= 'INC000000802824'
GROUP?= 'SSI Internal'
USER?= 'tskirvin'

default: ticket-list

ticket-new:
	@echo "new"
	@echo "Testing" | ../usr/bin/snow-ticket-create --subject testing \
		--group $(GROUP) --ticket new-cis-ticket.yaml

ticket-list:
	@echo "list"
	@ ../usr/bin/snow-ticket-list -g $(GROUP)

ticket:
	@echo "ticket"
	@ ../usr/bin/snow-ticket $(INCIDENT)

ticket-journal:
	@echo "adding journal"
	@ ../usr/bin/snow-ticket-journal $(INCIDENT) 'testing again'

ticket-assign:
	@echo "assigning"
	@ ../usr/bin/snow-ticket-assign $(INCIDENT) -u $(USER) -g $(GROUP)

ticket-unassign:
	@echo "unassign"
	@ ../usr/bin/snow-ticket-unassign $(INCIDENT)

ticket-resolve:
	@echo "resolve"
	@ ../usr/bin/snow-ticket-resolve $(INCIDENT) 'testing'

ticket-reopen:
	@echo "reopen"
	@ ../usr/bin/snow-ticket-reopen $(INCIDENT)

ticket-all: ticket-new ticket-list ticket ticket-journal ticket-assign ticket-unassign ticket-resolve ticket-reopen

ritm-new:
	@echo "Testing" | ../usr/bin/snow-ticket-create --subject testing \
		--type ritm --group $(GROUP) --ticket new-cis-ritm.yaml --debug

ritm-list:
	@ ../usr/bin/snow-ticket-list --group $(GROUP) --type ritm
