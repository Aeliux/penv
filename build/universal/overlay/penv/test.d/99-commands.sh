#!/bin/sh
# Test: Essential and Optional Commands
# Validates presence of critical commands in the rootfs

# Read list of essential commands from /penv/test.d/required.d/
commands=""
if [ -d /penv/test.d/required.d/ ]; then
  for f in /penv/test.d/required.d/*; do
    [ -f "$f" ] && commands="$commands$(cat "$f")"'\n'
  done
fi

commands="$commands"':\n'

# Read list of optional commands from /penv/test.d/optional.d/
if [ -d /penv/test.d/optional.d/ ]; then
  for f in /penv/test.d/optional.d/*; do
    [ -f "$f" ] && commands="$commands$(cat "$f")"'\n'
  done
fi

optional=0


# Write commands to a temporary file
tmpfile=$(mktemp)
printf "%b" "$commands" > "$tmpfile"

while IFS= read -r line || [ -n "$line" ]; do
  # strip comments after fields and trim whitespace
  # remove inline comment if whole line starts with # is handled later
  # trim leading/trailing whitespace using sed (portable)
  line=$(printf '%s\n' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
  [ -z "$line" ] && continue       # skip blank
  case "$line" in
    \#*) continue ;;               # skip comment lines
    \:) optional=1; continue ;;
  esac
  # take first token as command name
  set -- $line
  cmd=$1
  test_start "Command '$cmd' exists"
  if test_command_exists "$cmd"; then
      test_pass
  else
      cls=fail
      [ $optional -eq 1 ] && cls=skip
      "test_$cls" "Command '$cmd' not found"
  fi
done < "$tmpfile"
rm -f "$tmpfile"