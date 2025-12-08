# Makefile for penv project
.PHONY: all build clean test coverage fmt vet lint install help

# Variables
PREFIX ?= /usr/local
BINARY_DIR := bin
CLIENT_BINARY := $(BINARY_DIR)/client
PINIT_BINARY := $(BINARY_DIR)/pinit
GO ?= go
GOPATH ?= $(shell $(GO) env GOPATH)
GOFLAGS ?= -v -trimpath
LDFLAGS ?= -s -w -extldflags "-static"
CFLAGS ?= -Os -ffunction-sections -fdata-sections
CLDFLAGS ?= -Wl,--gc-sections

all: clean test build ## Run all tests and build binaries

build: rootbox client pinit ## Build all binaries

rootbox: ## Build rootbox binary
	@echo "Building RootBox..."
	@mkdir -p $(BINARY_DIR)
	$(CC) $(CFLAGS) -Wall -o $(BINARY_DIR)/rootbox ./src/rootbox.c $(CLDFLAGS) -static -s
	@echo "RootBox built successfully: $(BINARY_DIR)/rootbox"

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

install: ## Install client to $PREFIX/bin
	@echo "Installing client..."
	install -Dm755 $(CLIENT_BINARY) $(PREFIX)/bin/penv
	@echo "Client installed to $(PREFIX)/bin/penv"

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
