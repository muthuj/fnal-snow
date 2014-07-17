new-ticket:
	@echo "Testing" | ../usr/sbin/nagios-to-snow --type testing \
		--ciname testing --subject testing --serviceproblemid testing

host: problem-host recovery-host

problem-host:
	@echo "(sample)" | ../usr/sbin/nagios-to-snow --type PROBLEM \
		--ciname testing --state DOWN \
		--subject "fake alert: problem with fake host testing" \
		--debug

ack-host:
	echo "(sample)" | ../usr/sbin/nagios-to-snow --type ACKNOWLEDGEMENT \
		--ciname testing --state DOWN \
		--subject "fake alert: problem with fake host testing" \
		--debug

recovery-host:
	@echo "(sample)" | ../usr/sbin/nagios-to-snow --type RECOVERY \
		--ciname testing --state UP \
		--subject "fake alert: problem with fake host testing" \
		--debug

problem-service:
	@echo "(sample)" | ../usr/sbin/nagios-to-snow --type PROBLEM \
		--ciname testing --servicename test_svc \
		--subject "fake alert: problem with fake service testing" \
		--debug

ack-service:
	@echo "(sample)" | ../usr/sbin/nagios-to-snow --type ACKNOWLEDGEMENT \
		--ciname testing --servicename test_svc \
		--subject "fake alert: problem with fake service testing" \
		--ackauthor=`whoami` --ackcomment="testing" \
		--debug 

recovery-service:
	@echo "(sample)" | ../usr/sbin/nagios-to-snow --type RECOVERY \
		--ciname testing --servicename test_svc \
		--subject "fake alert: problem with fake service testing" \
		--debug 
