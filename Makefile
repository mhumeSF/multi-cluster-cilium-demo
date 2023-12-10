.PHONY: up down
# Makefile

# Target for 'make up'
up:
	./build-cluster.sh

# Target for 'make down'
down:
	kind delete clusters c1 c2

