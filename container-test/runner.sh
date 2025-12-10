#!/bin/sh
# In-container test runner

# Colors for output  
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Test results counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_WARNED=0
TESTS_SKIPPED=0
TOTAL_TESTS=0

# Configuration from environment
VERBOSE="${VERBOSE:-0}"
STOP_ON_FAIL="${STOP_ON_FAIL:-0}"
TEST_CATEGORY="${TEST_CATEGORY:-all}"
RUNNING_AS_ROOT="${RUNNING_AS_ROOT:-0}"

# Logging functions
log_pass() {
    printf "${GREEN}[PASS]${NC} %s\n" "$1"
    TESTS_PASSED=$((TESTS_PASSED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

log_fail() {
    printf "${RED}[FAIL]${NC} %s\n" "$1"
    [ -n "$2" ] && printf "       Details: %s\n" "$2"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
    
    if [ "$STOP_ON_FAIL" -eq 1 ]; then
        printf "${RED}[ERROR]${NC} Stopping on first failure\n"
        exit 1
    fi
}

log_warn() {
    printf "${YELLOW}[WARN]${NC} %s\n" "$1"
    [ -n "$2" ] && printf "       Details: %s\n" "$2"
    TESTS_WARNED=$((TESTS_WARNED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

log_skip() {
    printf "${BLUE}[SKIP]${NC} %s\n" "$1"
    [ -n "$2" ] && printf "       Reason: %s\n" "$2"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    TOTAL_TESTS=$((TOTAL_TESTS + 1))
}

log_info() {
    printf "${BLUE}[INFO]${NC} %s\n" "$1"
}

log_section() {
    printf "\n"
    printf "==========================================\n"
    printf "%s\n" "$1"
    printf "==========================================\n"
}

# Helper: Skip test if requires root and we're rootless
skip_if_rootless() {
    if [ "$RUNNING_AS_ROOT" -eq 0 ]; then
        log_skip "$1" "Requires root privileges"
        return 0
    fi
    return 1
}

# Helper: Run command (inside container already)
run_in_container() {
    eval "$1" 2>&1
    return $?
}

# Helper: Check if command succeeded (should NOT succeed for security)
test_escape_blocked() {
    local description="$1"
    local cmd="$2"
    
    if [ "$VERBOSE" -eq 1 ]; then
        log_info "Testing: $description"
        log_info "Command: $cmd"
    fi
    
    local output
    output=$(eval "$cmd" 2>&1)
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        log_fail "$description" "Command succeeded (should have been blocked)"
        [ "$VERBOSE" -eq 1 ] && printf "       Output: %s\n" "$output"
        return 1
    else
        log_pass "$description"
        [ "$VERBOSE" -eq 1 ] && printf "       Output: %s\n" "$output"
        return 0
    fi
}

# Helper: Check if command failed (should succeed for functionality)
test_functionality() {
    local description="$1"
    local cmd="$2"
    
    if [ "$VERBOSE" -eq 1 ]; then
        log_info "Testing: $description"
        log_info "Command: $cmd"
    fi
    
    local output
    output=$(eval "$cmd" 2>&1)
    local ret=$?
    
    if [ $ret -eq 0 ]; then
        log_pass "$description"
        [ "$VERBOSE" -eq 1 ] && printf "       Output: %s\n" "$output"
        return 0
    else
        log_fail "$description" "Command failed (should have succeeded)"
        [ "$VERBOSE" -eq 1 ] && printf "       Output: %s\n" "$output"
        return 1
    fi
}

# Run test files
run_test_file() {
    local test_file="$1"
    
    if [ ! -f "$test_file" ]; then
        log_warn "Test file not found: $test_file"
        return
    fi
    
    log_section "Running: $(basename "$test_file")"
    
    # Source the test file
    . "$test_file"
}

# Main test execution
run_tests() {
    local test_dir="/.rootbox-tests/tests"
    
    if [ ! -d "$test_dir" ]; then
        printf "${RED}[ERROR]${NC} Tests directory not found: $test_dir\n"
        exit 1
    fi
    
    # Determine which tests to run
    case "$TEST_CATEGORY" in
        namespace)
            run_test_file "$test_dir/01-namespace-escape.sh"
            ;;
        filesystem)
            run_test_file "$test_dir/02-filesystem-escape.sh"
            ;;
        privilege)
            run_test_file "$test_dir/03-privilege-escalation.sh"
            ;;
        resource)
            run_test_file "$test_dir/04-resource-isolation.sh"
            ;;
        device)
            run_test_file "$test_dir/05-device-access.sh"
            ;;
        procfs)
            run_test_file "$test_dir/06-procfs-sysfs.sh"
            ;;
        network)
            run_test_file "$test_dir/07-network-isolation.sh"
            ;;
        overlayfs)
            run_test_file "$test_dir/08-overlayfs-escape.sh"
            ;;
        infoleak)
            run_test_file "$test_dir/09-information-leak.sh"
            ;;
        chains)
            run_test_file "$test_dir/10-exploitation-chains.sh"
            ;;
        all|*)
            for test_file in "$test_dir"/*.sh; do
                [ -f "$test_file" ] && run_test_file "$test_file"
            done
            ;;
    esac
}

# Print final summary
print_summary() {
    printf "\n"
    log_section "Test Summary"
    printf "Total Tests:  %d\n" "$TOTAL_TESTS"
    printf "${GREEN}Passed:${NC}       %d\n" "$TESTS_PASSED"
    printf "${RED}Failed:${NC}       %d\n" "$TESTS_FAILED"
    printf "${YELLOW}Warnings:${NC}     %d\n" "$TESTS_WARNED"
    printf "${BLUE}Skipped:${NC}      %d\n" "$TESTS_SKIPPED"
    printf "\n"
    
    if [ $TESTS_FAILED -gt 0 ]; then
        printf "${RED}SECURITY VULNERABILITIES DETECTED!${NC}\n"
        printf "Review the failed tests above for details.\n"
        return 1
    elif [ $TESTS_WARNED -gt 0 ]; then
        printf "${YELLOW}WARNING: Potential security issues detected.${NC}\n"
        printf "Review the warnings above for details.\n"
        return 0
    else
        printf "${GREEN}All security tests passed!${NC}\n"
        return 0
    fi
}

# Run tests
run_tests
print_summary
exit $?
