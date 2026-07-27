.PHONY: install check doctor update backup

install:
	./install.sh

check:
	bash -n install.sh scripts/*.sh

doctor:
	scripts/doctor.sh "$(PWD)"

update:
	scripts/update.sh "$(PWD)"

backup:
	scripts/backup.sh "$(PWD)"
