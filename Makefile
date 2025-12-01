# Makefile for penv project
.PHONY: all build clean test coverage fmt vet lint install help

# Variables
BINARY_DIR := bin
CLIENT_BINARY := $(BINARY_DIR)/client
PINIT_BINARY := $(BINARY_DIR)/pinit
GO := go
GOFLAGS := -v
LDFLAGS := -s -w

# Colors for output
CYAN := \033[0;36m
GREEN := \033[0;32m
RESET := \033[0m

all: clean fmt vet test build ## Run all checks and build binaries

build: build-client build-pinit ## Build all binaries

build-client: ## Build client binary
	@echo "$(CYAN)Building client...$(RESET)"
	@mkdir -p $(BINARY_DIR)
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(CLIENT_BINARY) ./cmd/client
	@echo "$(GREEN)✓ Client built successfully: $(CLIENT_BINARY)$(RESET)"

build-pinit: ## Build pinit binary
	@echo "$(CYAN)Building pinit...$(RESET)"
	@mkdir -p $(BINARY_DIR)
	$(GO) build $(GOFLAGS) -ldflags "$(LDFLAGS)" -o $(PINIT_BINARY) ./cmd/pinit
	@echo "$(GREEN)✓ Pinit built successfully: $(PINIT_BINARY)$(RESET)"

install: ## Install binaries to $GOPATH/bin
	@echo "$(CYAN)Installing binaries...$(RESET)"
	$(GO) install ./cmd/client
	$(GO) install ./cmd/pinit
	@echo "$(GREEN)✓ Binaries installed$(RESET)"

test: ## Run tests
	@echo "$(CYAN)Running tests...$(RESET)"
	$(GO) test -v -race ./...
	@echo "$(GREEN)✓ Tests passed$(RESET)"

coverage: ## Run tests with coverage
	@echo "$(CYAN)Running tests with coverage...$(RESET)"
	$(GO) test -v -race -coverprofile=coverage.out -covermode=atomic ./...
	$(GO) tool cover -html=coverage.out -o coverage.html
	@echo "$(GREEN)✓ Coverage report generated: coverage.html$(RESET)"

bench: ## Run benchmarks
	@echo "$(CYAN)Running benchmarks...$(RESET)"
	$(GO) test -bench=. -benchmem ./...

fmt: ## Format code
	@echo "$(CYAN)Formatting code...$(RESET)"
	$(GO) fmt ./...
	@echo "$(GREEN)✓ Code formatted$(RESET)"

vet: ## Run go vet
	@echo "$(CYAN)Running go vet...$(RESET)"
	$(GO) vet ./...
	@echo "$(GREEN)✓ Vet passed$(RESET)"

lint: ## Run golangci-lint (requires golangci-lint to be installed)
	@echo "$(CYAN)Running linter...$(RESET)"
	@which golangci-lint > /dev/null || (echo "golangci-lint not found. Install it from https://golangci-lint.run/usage/install/" && exit 1)
	golangci-lint run ./...
	@echo "$(GREEN)✓ Lint passed$(RESET)"

mod-tidy: ## Tidy go modules
	@echo "$(CYAN)Tidying go modules...$(RESET)"
	$(GO) mod tidy
	@echo "$(GREEN)✓ Modules tidied$(RESET)"

mod-download: ## Download go modules
	@echo "$(CYAN)Downloading go modules...$(RESET)"
	$(GO) mod download
	@echo "$(GREEN)✓ Modules downloaded$(RESET)"

clean: ## Clean build artifacts
	@echo "$(CYAN)Cleaning...$(RESET)"
	@rm -rf $(BINARY_DIR)
	@rm -f coverage.out coverage.html
	@echo "$(GREEN)✓ Cleaned$(RESET)"

run-client: build-client ## Build and run client
	@echo "$(CYAN)Running client...$(RESET)"
	@./$(CLIENT_BINARY)

run-pinit: build-pinit ## Build and run pinit
	@echo "$(CYAN)Running pinit...$(RESET)"
	@./$(PINIT_BINARY)

deps: ## List dependencies
	@echo "$(CYAN)Dependencies:$(RESET)"
	$(GO) list -m all

help: ## Show this help message
	@echo "$(CYAN)Available targets:$(RESET)"
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "  $(GREEN)%-15s$(RESET) %s\n", $$1, $$2}'
