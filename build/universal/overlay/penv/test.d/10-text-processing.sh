#!/bin/sh
# Test: Advanced Text Processing
# Validates text manipulation tools work correctly

test_start "sed can perform substitution"
if output=$(echo "hello world" | sed 's/world/universe/' 2>&1) && [ "$output" = "hello universe" ]; then
    test_pass
else
    test_fail "sed substitution failed"
fi

test_start "sed can delete lines"
if output=$(printf "line1\nline2\nline3\n" | sed '2d' 2>&1 | wc -l | tr -d ' ') && [ "$output" -eq 2 ]; then
    test_pass
else
    test_fail "sed line deletion failed"
fi

test_start "awk can process fields"
if output=$(echo "a b c" | awk '{print $2}' 2>&1) && [ "$output" = "b" ]; then
    test_pass
else
    test_fail "awk field processing failed"
fi

test_start "awk can perform arithmetic"
if output=$(echo "5 10" | awk '{print $1 + $2}' 2>&1) && [ "$output" = "15" ]; then
    test_pass
else
    test_fail "awk arithmetic failed"
fi

test_start "grep supports regular expressions"
if echo "test123" | grep -q '[0-9]\+' 2>/dev/null; then
    test_pass
else
    test_fail "grep regex failed"
fi

test_start "grep can count matches"
if output=$(printf "line\nline\nother" | grep -c "line" 2>&1) && [ "$output" = "2" ]; then
    test_pass
else
    test_fail "grep count failed"
fi

test_start "grep supports case-insensitive search"
if echo "TeSt" | grep -qi "test" 2>/dev/null; then
    test_pass
else
    test_fail "grep case-insensitive search failed"
fi

test_start "cut command exists and works"
if test_command_exists cut && output=$(echo "a:b:c" | cut -d: -f2) && [ "$output" = "b" ]; then
    test_pass
else
    test_fail "cut command failed"
fi

test_start "sort command works correctly"
if output=$(printf "3\n1\n2" | sort -n 2>&1 | tr '\n' ' ') && [ "$output" = "1 2 3 " ]; then
    test_pass
else
    test_fail "sort command failed"
fi

test_start "uniq command removes duplicates"
if output=$(printf "a\na\nb" | uniq 2>&1 | wc -l) && [ "$output" -eq 2 ]; then
    test_pass
else
    test_fail "uniq command failed"
fi

test_start "tr command translates characters"
if output=$(echo "abc" | tr 'a-z' 'A-Z' 2>&1) && [ "$output" = "ABC" ]; then
    test_pass
else
    test_fail "tr command failed"
fi

test_start "wc can count lines"
if output=$(printf "line1\nline2\nline3\n" | wc -l 2>&1 | tr -d ' ') && [ "$output" -eq 3 ]; then
    test_pass
else
    test_fail "wc line count failed"
fi

test_start "wc can count words"
if output=$(echo "one two three" | wc -w 2>&1) && [ "$output" -eq 3 ]; then
    test_pass
else
    test_fail "wc word count failed"
fi

test_start "head command shows first lines"
if output=$(printf "1\n2\n3\n4\n5" | head -n 2 2>&1 | wc -l) && [ "$output" -eq 2 ]; then
    test_pass
else
    test_fail "head command failed"
fi

test_start "tail command shows last lines"
if output=$(printf "1\n2\n3\n4\n5\n" | tail -n 2 2>&1 | wc -l | tr -d ' ') && [ "$output" -eq 2 ]; then
    test_pass
else
    test_fail "tail command failed"
fi
