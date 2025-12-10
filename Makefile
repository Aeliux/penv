# Makefile for penv project
.PHONY: all build clean test coverage fmt vet lint install help

# Variables
PREFIX ?= /usr/local

BINARY_DIR := bin
CLIENT_BINARY := $(BINARY_DIR)/client
PINIT_BINARY := $(BINARY_DIR)/pinit
ROOTBOX_BINARY := $(BINARY_DIR)/rootbox

GO ?= go
GOPATH ?= $(shell $(GO) env GOPATH)

GOFLAGS ?= -v -trimpath
LDFLAGS ?= -s -w
CFLAGS ?= -Os -ffunction-sections -fdata-sections
CLDFLAGS ?= -Wl,--gc-sections

all: clean test build ## Run all tests and build binaries

build: rootbox client pinit ## Build all binaries

rootbox: ## Build rootbox binary
	@echo "Building RootBox..."
	@mkdir -p $(BINARY_DIR)
	$(CC) $(CFLAGS) -Wall -o $(ROOTBOX_BINARY) \
		./src/rootbox/main.c \
		./src/rootbox/utils.c \
		./src/rootbox/namespace.c \
		./src/rootbox/mount.c \
		./src/rootbox/pty.c \
		./src/rootbox/overlayfs.c \
		$(CLDFLAGS) -lutil -s
	@ln -sf rootbox $(BINARY_DIR)/rootbox-ofs
	@echo "RootBox built successfully: $(ROOTBOX_BINARY)"
	@echo "OverlayFS symlink created: $(BINARY_DIR)/rootbox-ofs"

client: ## Build client binary
	@echo "Building client..."
	@mkdir -p $(BINARY_DIR)
	CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(CLIENT_BINARY) ./src/client
	@echo "Client built successfully: $(CLIENT_BINARY)"

pinit: ## Build pinit binary
	@echo "Building pinit..."
	@mkdir -p $(BINARY_DIR)
	CGO_ENABLED=0 $(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(PINIT_BINARY) ./src/pinit
	@echo "Pinit built successfully: $(PINIT_BINARY)"

install: ## Install penv client to $PREFIX/bin
	@echo "Installing penv binaries..."
	install -Dm755 $(CLIENT_BINARY) $(PREFIX)/bin/penv
	install -Dm755 $(ROOTBOX_BINARY) $(PREFIX)/bin/rootbox
	@echo "Binaries installed to $(PREFIX)/bin"
	@if command -v apparmor_parser >/dev/null 2>&1; then \
		echo "Installing AppArmor profile..."; \
		install -Dm644 ./src/rootbox/apparmor.profile /etc/apparmor.d/penv-rootbox; \
		if apparmor_parser -r /etc/apparmor.d/penv-rootbox 2>/dev/null; then \
			echo "AppArmor profile installed and loaded"; \
		else \
			echo "Warning: Failed to load AppArmor profile (may need sudo)"; \
		fi; \
	else \
		echo "AppArmor not detected, skipping profile installation"; \
	fi
	@echo "Installing sysctl configuration for unprivileged ping..."
	@install -Dm644 ./src/rootbox/sysctl.conf /etc/sysctl.d/99-penv.conf
	@if command -v sysctl >/dev/null 2>&1; then \
		sysctl -p /etc/sysctl.d/99-penv.conf >/dev/null 2>&1 || echo "Warning: Failed to apply sysctl (may need sudo)"; \
	fi
	@echo "Installation complete!"

test: ## Run tests
	@echo "Running tests..."
	$(GO) test -v -race -shuffle=on -count=1 -failfast penv/...
	@echo "Tests passed"

coverage: ## Run tests with coverage
	@echo "Running tests with coverage..."
	$(GO) test -v -race -coverprofile=coverage.out -covermode=atomic penv/...
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "Coverage report generated: coverage.html"

bench: ## Run benchmarks
	@echo "Running benchmarks..."
	$(GO) test -bench=. -benchmem penv/...

fmt: ## Format code
	@echo "Formatting code..."
	@find src -name "*.go" -exec gofmt -w {} +
	@echo "Code formatted"

vet: ## Run go vet
	@echo "Running go vet..."
	$(GO) vet penv/...
	@echo "Vet passed"

lint: ## Run golangci-lint (requires golangci-lint to be installed)
	@echo "Running linter..."
	$(GOPATH)/bin/golangci-lint run ./src/...
	@echo "Lint passed"

clean: ## Clean build artifacts
	@echo "Cleaning..."
	@rm -rf $(BINARY_DIR)
	@rm -f coverage.out coverage.html
	@echo "Cleaned"

deps: ## List dependencies
	@echo "Dependencies:"
	$(GO) list -m all

help: ## Show this help message
	@echo "Available targets:"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  %-15s %s\n", $$1, $$2}'
