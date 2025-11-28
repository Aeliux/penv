#!/bin/sh
# /penv/test.sh
# Main test runner for validating rootfs functionality

set -e

# Color codes for output
if [ -t 1 ]; then
    C_RED='\033[0;31m'
    C_GREEN='\033[0;32m'
    C_YELLOW='\033[0;33m'
    C_BLUE='\033[0;34m'
    C_CYAN='\033[0;36m'
    C_BOLD='\033[1m'
    C_RESET='\033[0m'
else
    C_RED=''
    C_GREEN=''
    C_YELLOW=''
    C_BLUE=''
    C_CYAN=''
    C_BOLD=''
    C_RESET=''
fi

# Test counters
TESTS_TOTAL=0
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_SKIPPED=0

# tests tracking
FAILED_TESTS=""
SKIPPED_TESTS=""

# Test result functions
test_start() {
    name="$1"
    CURRENT_TEST="$name"
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    printf "${C_BLUE}[TEST]${C_RESET} %-50s " "$name"
}

test_pass() {
    TESTS_PASSED=$((TESTS_PASSED + 1))
    printf "${C_GREEN}✓ PASS${C_RESET}\n"
}

test_fail() {
    reason="$1"
    TESTS_FAILED=$((TESTS_FAILED + 1))
    printf "${C_RED}✗ FAIL${C_RESET}\n"
    if [ -n "$reason" ]; then
        printf "${C_RED}       └─ %s${C_RESET}\n" "$reason"
    fi
    FAILED_TESTS="${FAILED_TESTS}${CURRENT_TEST}: ${reason}\n"
}

test_skip() {
    reason="$1"
    TESTS_SKIPPED=$((TESTS_SKIPPED + 1))
    printf "${C_YELLOW}⊘ SKIP${C_RESET}\n"
    if [ -n "$reason" ]; then
        printf "${C_YELLOW}       └─ %s${C_RESET}\n" "$reason"
    fi
    SKIPPED_TESTS="${SKIPPED_TESTS}${CURRENT_TEST}: ${reason}\n"
}

# Helper to run a test command
run_test() {
    output=""
    exit_code=0
    
    output=$("$@" 2>&1) || exit_code=$?
    exit_code=${exit_code:-0}
    
    if [ $exit_code -eq 0 ]; then
        return 0
    else
        echo "$output" >&2
        return $exit_code
    fi
}

# Test file existence
test_file_exists() {
    file="$1"
    [ -f "$file" ]
}

# Test directory existence
test_dir_exists() {
    dir="$1"
    [ -d "$dir" ]
}

# Test command availability
test_command_exists() {
    cmd="$1"
    command -v "$cmd" >/dev/null 2>&1
}

# Test executable permission
test_executable() {
    file="$1"
    [ -x "$file" ]
}

# Test symlink
test_symlink() {
    link="$1"
    [ -L "$link" ]
}

# Header function
print_header() {
    printf "\n"
    printf "${C_BOLD}${C_CYAN}========================================${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}%s${C_RESET}\n" "$1"
    printf "${C_BOLD}${C_CYAN}========================================${C_RESET}\n"
    printf "\n"
}

# Print summary
print_summary() {
    printf "\n"
    printf "${C_BOLD}${C_CYAN}========================================${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}TEST SUMMARY${C_RESET}\n"
    printf "${C_BOLD}${C_CYAN}========================================${C_RESET}\n"
    printf "\n"
    echo "Total Tests:   $TESTS_TOTAL"
    printf "${C_GREEN}Passed:        %s${C_RESET}\n" "$TESTS_PASSED"
    printf "${C_RED}Failed:        %s${C_RESET}\n" "$TESTS_FAILED"
    printf "${C_YELLOW}Skipped:       %s${C_RESET}\n" "$TESTS_SKIPPED"
    printf "\n"
    
    if [ $TESTS_FAILED -gt 0 ] || [ $TESTS_SKIPPED -gt 0 ]; then
        if [ $TESTS_SKIPPED -gt 0 ]; then
            printf "${C_BOLD}${C_YELLOW}SKIPPED TESTS:${C_RESET}\n"
            printf "${C_YELLOW}----------------------------------------${C_RESET}\n"
            printf "${C_YELLOW}%b${C_RESET}" "$SKIPPED_TESTS"
            printf "${C_YELLOW}----------------------------------------${C_RESET}\n"
            printf "\n"
        fi
        
        if [ $TESTS_FAILED -gt 0 ]; then
            printf "${C_BOLD}${C_RED}FAILED TESTS:${C_RESET}\n"
            printf "${C_RED}----------------------------------------${C_RESET}\n"
            printf "${C_RED}%b${C_RESET}" "$FAILED_TESTS"
            printf "${C_RED}----------------------------------------${C_RESET}\n"
            printf "\n"
        fi
    fi
    
    if [ $TESTS_FAILED -gt 0 ]; then
        printf "${C_BOLD}${C_RED}SOME TESTS FAILED!${C_RESET}\n"
        printf "\n"
        return 2
    elif [ $TESTS_SKIPPED -gt 0 ]; then
        printf "${C_BOLD}${C_YELLOW}SOME TESTS WERE SKIPPED!${C_RESET}\n"
        printf "\n"
        return 1
    else
        printf "${C_BOLD}${C_GREEN}ALL TESTS PASSED!${C_RESET}\n"
        printf "\n"
        return 0
    fi
}

# Main test execution
main() {
    print_header "penv rootfs Test Suite"
    
    # Display environment info
    printf "${C_CYAN}Environment Information:${C_RESET}\n"
    echo "  Penv Version:    ${PENV_VERSION:-unknown}"
    echo "  Distro:          ${PENV_METADATA_DISTRO:-unknown}"
    echo "  Family:          ${PENV_METADATA_FAMILY:-unknown}"
    echo "  Timestamp:       ${PENV_METADATA_TIMESTAMP:-unknown}"
    printf "\n"
    
    # Run universal tests
    if [ -d /penv/test.d ]; then
        for test_file in /penv/test.d/*; do
            if [ -f "$test_file" ] && [ -x "$test_file" ]; then
                test_name=$(basename "$test_file")
                print_header "Running Test Suite: $test_name"
                
                # Source the test file to run its tests
                . "$test_file" || true
                printf "\n"
            fi
        done
    else
        printf "${C_YELLOW}Warning: /penv/test.d directory not found${C_RESET}\n"
        printf "\n"
    fi
    
    # Print final summary
    print_summary
}

# Run main function
main "$@"
