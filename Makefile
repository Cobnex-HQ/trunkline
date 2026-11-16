.PHONY: setup doctor build install ios test
setup doctor build install ios test:
	python3 Scripts/dev.py $@
