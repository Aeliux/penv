#!/bin/sh
# Test: Advanced Scripting Features
# Validates shell scripting capabilities

TEST_DIR="/tmp/penv-script-test-$$"

setup_test_env() {
    mkdir -p "$TEST_DIR" 2>/dev/null || return 1
    return 0
}

cleanup_test_env() {
    rm -rf "$TEST_DIR" 2>/dev/null || true
}

trap cleanup_test_env EXIT INT TERM

test_start "Setup scripting test environment"
if setup_test_env; then
    test_pass
else
    test_fail "Cannot create test directory"
fi

test_start "Functions can be defined and called"
result=$(
    test_func() {
        echo "function works"
    }
    test_func
)
if [ "$result" = "function works" ]; then
    test_pass
else
    test_fail "Function definition/call failed"
fi

test_start "Functions can accept parameters"
result=$(
    param_func() {
        echo "$1 $2"
    }
    param_func "hello" "world"
)
if [ "$result" = "hello world" ]; then
    test_pass
else
    test_fail "Function parameters failed"
fi

test_start "Local variables work in functions (bash)"
if bash -c '
    global="global"
    test_local() {
        local local_var="local"
        global="modified"
        echo "$local_var"
    }
    test_local
    [ "$global" = "modified" ]
' 2>/dev/null; then
    test_pass
else
    test_fail "local keyword not working in bash"
fi

test_start "Case statement works"
result=$(
    value="test"
    case "$value" in
        test) echo "matched" ;;
        *) echo "no match" ;;
    esac
)
if [ "$result" = "matched" ]; then
    test_pass
else
    test_fail "Case statement failed"
fi

test_start "Case with multiple patterns works"
result=$(
    value="b"
    case "$value" in
        a|b|c) echo "matched" ;;
        *) echo "no match" ;;
    esac
)
if [ "$result" = "matched" ]; then
    test_pass
else
    test_fail "Case with multiple patterns failed"
fi

test_start "While loop works"
result=$(
    i=0
    while [ $i -lt 3 ]; do
        i=$((i + 1))
    done
    echo $i
)
if [ "$result" = "3" ]; then
    test_pass
else
    test_fail "While loop failed (got: $result)"
fi

test_start "Until loop works"
result=$(
    i=0
    until [ $i -eq 3 ]; do
        i=$((i + 1))
    done
    echo $i
)
if [ "$result" = "3" ]; then
    test_pass
else
    test_fail "Until loop failed"
fi

test_start "For loop with list works"
result=$(
    sum=0
    for i in 1 2 3; do
        sum=$((sum + i))
    done
    echo $sum
)
if [ "$result" = "6" ]; then
    test_pass
else
    test_fail "For loop failed (got: $result)"
fi

test_start "For loop with glob expansion"
if touch "$TEST_DIR/test1" "$TEST_DIR/test2" "$TEST_DIR/test3" 2>/dev/null; then
    count=$(
        c=0
        for f in "$TEST_DIR"/test*; do
            c=$((c + 1))
        done
        echo $c
    )
    if [ "$count" = "3" ]; then
        test_pass
    else
        test_fail "For loop glob expansion failed (got $count)"
    fi
else
    test_fail "Cannot create test files"
fi

test_start "Break statement works in loops"
result=$(
    i=0
    while true; do
        i=$((i + 1))
        [ $i -eq 5 ] && break
        [ $i -gt 10 ] && break
    done
    echo $i
)
if [ "$result" = "5" ]; then
    test_pass
else
    test_fail "Break statement failed"
fi

test_start "Continue statement works in loops"
result=$(
    sum=0
    for i in 1 2 3 4 5; do
        [ $i -eq 3 ] && continue
        sum=$((sum + i))
    done
    echo $sum
)
if [ "$result" = "12" ]; then  # 1+2+4+5=12 (skipping 3)
    test_pass
else
    test_fail "Continue statement failed (got: $result)"
fi

test_start "Arithmetic expansion works"
result=$((5 + 3 * 2))
if [ "$result" -eq 11 ]; then
    test_pass
else
    test_fail "Arithmetic expansion failed (got: $result)"
fi

test_start "String length expansion"
if str="hello" && [ ${#str} -eq 5 ]; then
    test_pass
else
    test_fail "String length expansion failed"
fi

test_start "Parameter substitution with default"
result=${UNDEFINED_VAR:-"default"}
if [ "$result" = "default" ]; then
    test_pass
else
    test_fail "Parameter default substitution failed"
fi

test_start "Parameter substitution with assignment"
UNSET_VAR=""
result=${UNSET_VAR:="assigned"}
if [ "$result" = "assigned" ] && [ "$UNSET_VAR" = "assigned" ]; then
    test_pass
else
    test_fail "Parameter assignment substitution failed"
fi

test_start "Substring expansion works"
if str="hello world" && sub=${str#hello }; [ "$sub" = "world" ]; then
    test_pass
else
    test_skip "Substring expansion not fully supported"
fi

test_start "Test command with -n (non-empty string)"
if [ -n "non-empty" ]; then
    test_pass
else
    test_fail "Test -n failed"
fi

test_start "Test command with -z (empty string)"
if [ -z "" ]; then
    test_pass
else
    test_fail "Test -z failed"
fi

test_start "Test command with string equality"
if [ "abc" = "abc" ]; then
    test_pass
else
    test_fail "String equality test failed"
fi

test_start "Test command with string inequality"
if [ "abc" != "def" ]; then
    test_pass
else
    test_fail "String inequality test failed"
fi

test_start "Test command with numeric comparison"
if [ 5 -gt 3 ] && [ 3 -lt 5 ] && [ 5 -eq 5 ]; then
    test_pass
else
    test_fail "Numeric comparison failed"
fi

test_start "Logical AND (&&) operator works"
if true && true; then
    test_pass
else
    test_fail "Logical AND failed"
fi

test_start "Logical OR (||) operator works"
if false || true; then
    test_pass
else
    test_fail "Logical OR failed"
fi

test_start "Command substitution $() works"
result=$(echo "test")
if [ "$result" = "test" ]; then
    test_pass
else
    test_fail "Command substitution failed"
fi

test_start "Backtick command substitution works"
result=`echo "test"`
if [ "$result" = "test" ]; then
    test_pass
else
    test_fail "Backtick substitution failed"
fi
