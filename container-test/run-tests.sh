#!/bin/bash
# Container Security Test Suite - Main Runner
# Tests container isolation and escape vulnerabilities

# Configuration
VERBOSE=0
STOP_ON_FAIL=0
OUTPUT_FILE=""
ROOTBOX_MODE="ofs"
TEST_CATEGORY="all"
ROOTLESS_MODE=0
RUNNING_AS_ROOT=0
ROOTBOX_BIN=""
ROOTFS_PATH=""

# Find rootbox binaries
find_rootbox() {
    local search_paths=(
        "../bin/rootbox"
        "./bin/rootbox"
        "/usr/local/bin/rootbox"
        "/usr/bin/rootbox"
        "$(pwd)/../bin/rootbox"
    )
    
    for path in "${search_paths[@]}"; do
        if [ -x "$path" ]; then
            ROOTBOX_BIN="$(cd "$(dirname "$path")" && pwd)/$(basename "$path")"
            return 0
        fi
    done
    
    return 1
}

usage() {
    cat << 'EOF'
Usage: ./run-tests.sh [OPTIONS] <rootfs_path> [test_category]

Run container security tests against rootbox isolation.

Arguments:
    rootfs_path      Path to the rootfs directory to use as container root
    test_category    Optional: Run specific test category
                     (namespace|filesystem|privilege|resource|device|procfs|network|overlayfs|infoleak|chains|all)

Options:
    -v, --verbose           Show detailed output for each test
    -s, --stop-on-fail      Stop testing after first failure
    -o, --output FILE       Save test report to file
    -m, --mode MODE         Rootbox mode: 'ofs' (overlayfs) or 'direct' (default: ofs)
    -r, --rootless          Test rootless mode (no root required)
    -h, --help              Show this help message

Examples:
    ./run-tests.sh /path/to/rootfs                    # Test with overlayfs (default)
    ./run-tests.sh -m direct /path/to/rootfs          # Test direct mode
    ./run-tests.sh -v /path/to/rootfs namespace       # Verbose namespace tests
    sudo ./run-tests.sh /path/to/rootfs               # Test with root privileges
    ./run-tests.sh -o report.txt /path/to/rootfs      # Save report

EOF
    exit 0
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -v|--verbose)
                VERBOSE=1
                shift
                ;;
            -s|--stop-on-fail)
                STOP_ON_FAIL=1
                shift
                ;;
            -o|--output)
                OUTPUT_FILE="$2"
                shift 2
                ;;
            -m|--mode)
                ROOTBOX_MODE="$2"
                if [[ "$ROOTBOX_MODE" != "ofs" && "$ROOTBOX_MODE" != "direct" ]]; then
                    echo "ERROR: Invalid mode '$ROOTBOX_MODE'. Use 'ofs' or 'direct'"
                    exit 1
                fi
                shift 2
                ;;
            -r|--rootless)
                ROOTLESS_MODE=1
                shift
                ;;
            -h|--help)
                usage
                ;;
            *)
                if [ -z "$ROOTFS_PATH" ]; then
                    ROOTFS_PATH="$1"
                elif [ -z "$TEST_CATEGORY" ] || [ "$TEST_CATEGORY" = "all" ]; then
                    TEST_CATEGORY="$1"
                else
                    echo "ERROR: Unknown argument: $1"
                    usage
                fi
                shift
                ;;
        esac
    done
}

# Copy tests into rootfs
setup_tests_in_rootfs() {
    local test_dir="/.rootbox-tests"
    local target="$ROOTFS_PATH$test_dir"
    local script_dir="$(cd "$(dirname "$0")" && pwd)"
    
    echo "[INFO] Setting up tests in rootfs..."
    
    # Remove old tests if they exist
    rm -rf "$target" 2>/dev/null || true
    
    # Create test directory
    mkdir -p "$target/tests"
    
    # Copy all test scripts
    if [ -d "$script_dir/tests" ]; then
        cp "$script_dir/tests"/*.sh "$target/tests/" 2>/dev/null || true
    else
        echo "ERROR: Tests directory not found at $script_dir/tests"
        return 1
    fi
    
    # Copy the runner script
    if [ -f "$script_dir/runner.sh" ]; then
        cp "$script_dir/runner.sh" "$target/runner.sh"
        chmod +x "$target/runner.sh"
    else
        echo "ERROR: runner.sh not found at $script_dir/runner.sh"
        return 1
    fi
    
    echo "[INFO] Tests prepared in $test_dir"
}

# Cleanup tests from rootfs
cleanup_tests() {
    local test_dir="/.rootbox-tests"
    local target="$ROOTFS_PATH$test_dir"
    
    echo "[INFO] Cleaning up tests..."
    rm -rf "$target" 2>/dev/null || true
    
    # Clean up any test artifacts (files created during tests)
    # Be careful - only clean known test artifacts
    rm -rf "$ROOTFS_PATH/tmp/rootbox-test-"* 2>/dev/null || true
    rm -rf "$ROOTFS_PATH/tmp/escape"* 2>/dev/null || true
    rm -rf "$ROOTFS_PATH/tmp/test"* 2>/dev/null || true
}

# Main
main() {
    parse_args "$@"
    
    # Detect if running as root
    if [ "$EUID" -eq 0 ]; then
        RUNNING_AS_ROOT=1
    fi
    
    # Validate rootfs path
    if [ -z "$ROOTFS_PATH" ]; then
        echo "ERROR: No rootfs path specified"
        usage
    fi
    
    if [ ! -d "$ROOTFS_PATH" ]; then
        echo "ERROR: Rootfs path does not exist: $ROOTFS_PATH"
        exit 1
    fi
    
    # Find rootbox binary
    if ! find_rootbox; then
        echo "ERROR: rootbox binary not found. Please build it first."
        exit 1
    fi
    
    echo "=========================================="
    echo "Container Security Test Suite"
    echo "=========================================="
    echo "Rootfs:       $ROOTFS_PATH"
    echo "Rootbox:      $ROOTBOX_BIN"
    echo "Mode:         $ROOTBOX_MODE ($([ "$RUNNING_AS_ROOT" -eq 1 ] && echo "root" || echo "rootless"))"
    echo "Category:     $TEST_CATEGORY"
    echo "=========================================="
    echo ""
    
    # Warn about expected behavior differences
    if [ "$RUNNING_AS_ROOT" -eq 0 ]; then
        echo "[INFO] Running in rootless mode - some tests may behave differently"
    fi
    echo ""
    
    # Setup tests in rootfs
    setup_tests_in_rootfs
    
    # Prepare rootbox command
    local rootbox_cmd="$ROOTBOX_BIN"
    if [ "$ROOTBOX_MODE" = "direct" ]; then
        rootbox_cmd="$rootbox_cmd $ROOTFS_PATH"
    else
        # Use overlayfs mode (check for rootbox-ofs binary)
        local ofs_binary="${ROOTBOX_BIN%-*}-ofs"
        if [ -x "$ofs_binary" ]; then
            rootbox_cmd="$ofs_binary $ROOTFS_PATH"
        else
            # Exit if ofs binary not found
            echo "ERROR: OverlayFS mode selected but rootbox-ofs binary not found."
            cleanup_tests
            exit 1
        fi
    fi
    
    # Export variables for in-container runner
    export VERBOSE STOP_ON_FAIL TEST_CATEGORY RUNNING_AS_ROOT
    
    # Run tests inside container (single instance!)
    echo "[INFO] Starting container and running tests..."
    if [ -n "$OUTPUT_FILE" ]; then
        $rootbox_cmd -- /.rootbox-tests/runner.sh 2>&1 | tee "$OUTPUT_FILE"
        exit_code=${PIPESTATUS[0]}
    else
        $rootbox_cmd -- /.rootbox-tests/runner.sh
        exit_code=$?
    fi
    
    # Cleanup
    cleanup_tests
    
    exit $exit_code
}

main "$@"
