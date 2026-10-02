.PHONY: check build vm
check:
	python3 -m unittest discover -s tests -p 'test_*.py' -v
	python3 tools/check.py
build:
	sudo bash build.sh
vm:
	python3 tests/vm.py --iso $(ISO) --firmware $(or $(FIRMWARE),bios)
