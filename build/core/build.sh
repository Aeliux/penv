# build.sh - Functions to build and set up a root filesystem

set -e

readonly PENV_VERSION="2"
readonly PENV_BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export PENV_ENV_MODE="build"
export PENV_CONFIG_VERBOSE=1

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Validate required environment variables at source time
for _required_var in FAMILY DISTRO ROOTFS_DIR; do
    if [ -z "${!_required_var:-}" ]; then
        echo "Error: Required environment variable $_required_var is not set" >&2
        return 1 2>/dev/null || exit 1
    fi
done
unset _required_var

# Create a directory structure with multiple paths
_create_directories() {
    for dir in "$@"; do
        mkdir -p "$ROOTFS_DIR/$dir"
    done
}

# Write metadata files
_write_metadata() {
    # Plain text format
    echo "$PENV_VERSION" > "$ROOTFS_DIR"/penv/metadata/version
    echo "$FAMILY" > "$ROOTFS_DIR"/penv/metadata/family
    echo "$DISTRO" > "$ROOTFS_DIR"/penv/metadata/distro
    echo "$PENV_BUILD_TIMESTAMP" > "$ROOTFS_DIR"/penv/metadata/timestamp
    
    # JSON format
    cat > "$ROOTFS_DIR"/penv/metadata.json <<EOF
{
  "version": $PENV_VERSION,
  "family": "$FAMILY",
  "distro": "$DISTRO",
  "timestamp": "$PENV_BUILD_TIMESTAMP"
}
EOF

  # Shell format
  cat > "$ROOTFS_DIR"/penv/metadata.sh <<EOF
PENV_VERSION="$PENV_VERSION"
PENV_METADATA_FAMILY="$FAMILY"
PENV_METADATA_DISTRO="$DISTRO"
PENV_METADATA_TIMESTAMP="$PENV_BUILD_TIMESTAMP"
EOF
}

# Execute a command inside the chroot environment
# Usage: build::chroot [command...]
build::chroot() {
    local cmd=("$@")
    startup=("/bin/sh" -- "/penv/startup.sh")
    if [ "${#cmd[@]}" -eq 0 ]; then
        cmd=("${startup[@]}")
    else
        cmd=("${startup[@]}" "${cmd[@]}")
    fi
    
    local mounted_dev=0
    local mounted_proc=0
    local mounted_sys=0
    
    # Cleanup function for trap
    _cleanup_mounts() {
        local cleanup_exit_code=$?
        [ $mounted_sys -eq 1 ] && { umount -l "$ROOTFS_DIR/sys" || echo "Warning: Failed to unmount /sys" >&2; }
        [ $mounted_proc -eq 1 ] && { umount -l "$ROOTFS_DIR/proc" || echo "Warning: Failed to unmount /proc" >&2; }
        [ $mounted_dev -eq 1 ] && { umount -l "$ROOTFS_DIR/dev/pts" || echo "Warning: Failed to unmount /dev/pts" >&2; }
        [ $mounted_dev -eq 1 ] && { umount -l "$ROOTFS_DIR/dev/shm" || echo "Warning: Failed to unmount /dev/shm" >&2; }
        [ $mounted_dev -eq 1 ] && { umount -l "$ROOTFS_DIR/dev" || echo "Warning: Failed to unmount /dev" >&2; }
        return $cleanup_exit_code
    }
    
    # Set trap to cleanup on exit
    trap '_cleanup_mounts' EXIT
    
    # Mount essential filesystems
    if ! mount --bind /dev "$ROOTFS_DIR/dev"; then
        echo "Error: Failed to mount /dev" >&2
        return 1
    fi
    if ! mount --bind /dev/pts "$ROOTFS_DIR/dev/pts"; then
        echo "Error: Failed to mount /dev/pts" >&2
        return 1
    fi
    if ! mount --bind /dev/shm "$ROOTFS_DIR/dev/shm"; then
        echo "Error: Failed to mount /dev/shm" >&2
        return 1
    fi
    mounted_dev=1
    
    if ! mount -t proc proc "$ROOTFS_DIR/proc"; then
        echo "Error: Failed to mount /proc" >&2
        return 1
    fi
    mounted_proc=1
    
    if ! mount -t sysfs sys "$ROOTFS_DIR/sys"; then
        echo "Error: Failed to mount /sys" >&2
        return 1
    fi
    mounted_sys=1
    
    # Execute in chroot
    local exit_code=0
    set +e
    chroot "$ROOTFS_DIR" /bin/sh -c "$cmd" "$@"
    exit_code=$?
    set -e
    
    # Remove trap and cleanup explicitly
    trap - EXIT
    _cleanup_mounts
    
    return $exit_code
}

# Execute a script inside the chroot environment
# Usage: build::chroot_script <script-path>
build::chroot_script() {
    if [ "$#" -ne 1 ]; then
        echo "Usage: build::chroot_script <script-path>" >&2
        return 1
    fi
    
    local script_path="$1"
    local script_name
    script_name="$(basename "$script_path")"
    local relative_path="${script_path#$script_dir/}"
    local temp_script="/tmp/penv_${script_name}_$$"
    
    if [ ! -f "$script_path" ]; then
        echo "Error: Script not found: $script_path" >&2
        return 1
    fi
    
    echo "Executing $relative_path in chroot..."
    mkdir -p "$ROOTFS_DIR/tmp"
    
    # Copy script to temp location
    if ! cp "$script_path" "$ROOTFS_DIR$temp_script"; then
        echo "Error: Failed to copy script to chroot" >&2
        return 1
    fi
    
    chmod +x "$ROOTFS_DIR$temp_script"
    
    # Execute using build::chroot
    local exit_code=0
    build::chroot "/bin/sh $temp_script" || exit_code=$?
    
    # Clean up
    rm -f "$ROOTFS_DIR$temp_script"
    
    if [ $exit_code -ne 0 ]; then
        echo "Error: Script $relative_path failed with exit code $exit_code" >&2
        return $exit_code
    fi
    
    return 0
}

# Main setup function
build::setup() {
    if [ "$#" -ne 0 ]; then
        echo "Usage: build::setup" >&2
        return 1
    fi
    
    # Create penv directory structure
    _create_directories \
        penv \
        penv/metadata \
        penv/startup.d \
        penv/cleanup.d
    
    # Write metadata
    _write_metadata
    
    # Apply overlays to rootfs recursively
    echo "Applying overlays..."
    #run it for both universal and $DISTRO overlays
    for overlay in "universal" "$DISTRO"; do
        overlay_dir="$script_dir/build/$overlay/overlay"
        if [ -d "$overlay_dir" ]; then
            if ! cp -a "$overlay_dir/." "$ROOTFS_DIR/"; then
                echo "Error: Failed to apply overlay from $overlay_dir" >&2
                return 1
            fi
            # Verify copy
            echo "Verifying overlay files from $overlay_dir..."
            find "$overlay_dir" -type f | while read -r file; do
                relative_path="${file#$overlay_dir/}"
                if [ ! -e "$ROOTFS_DIR/$relative_path" ]; then
                    echo "Error: Overlay file missing in rootfs: $relative_path" >&2
                    return 1
                fi
            done
        fi
    done
    
    # Set up root user
    echo "Setting up root user..."
    cp -a "$ROOTFS_DIR/etc/skel/." "$ROOTFS_DIR/root/"
    
    # Apply patches inside chroot
    echo "Applying patches..."

    # make them executable first
    find "$ROOTFS_DIR/penv/patch.d" -type f -exec chmod +x {} \;
    export PENV_BUILD_STAGE="patch"
    if ! build::chroot; then
        echo "Error: Penv setup failed" >&2
        return 1
    fi
    unset PENV_BUILD_STAGE
    
    echo "Penv ${PENV_VERSION} setup completed successfully"
}

# Finalizr function
build::finalize() {
    # Remove patches
    echo "Removing patches..."
    rm -rvf "$ROOTFS_DIR/penv/patch.d"

    # Remove device files
    echo "Removing device files..."
    find "$ROOTFS_DIR/dev" -type c -o -type b | xargs rm -vf || true

    # Fix permissions for proot compatibility
    echo "Setting permissions..."
    # Ensure critical directories have proper permissions
    chmod 755 "$ROOTFS_DIR" || true
    chmod 755 "$ROOTFS_DIR/bin" || true
    chmod 755 "$ROOTFS_DIR/usr" "$ROOTFS_DIR/usr/bin" || true
    chmod 755 "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/sbin" || true
    chmod 755 "$ROOTFS_DIR/lib" || true
    chmod 755 "$ROOTFS_DIR/etc" || true
    chmod 1777 "$ROOTFS_DIR/tmp" || true
    chmod 755 "$ROOTFS_DIR/var" || true
    chmod 755 "$ROOTFS_DIR/opt" || true

    # Fix /root directory permissions
    if [ -d "$ROOTFS_DIR/root" ]; then
        chmod 700 "$ROOTFS_DIR/root"
    fi

    # Ensure all executables in bin directories are executable
    find "$ROOTFS_DIR/bin" "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" "$ROOTFS_DIR/usr/local/bin" "$ROOTFS_DIR/usr/local/sbin" \
        -type f -executable | while read -r file; do
        chmod 755 "$file" || true
    done

    # Fix library permissions
    find "$ROOTFS_DIR/lib" "$ROOTFS_DIR/usr/lib" -type f -name "*.so*" | while read -r file; do
        chmod 644 "$file" || true
    done

    # Fix dynamic linker permissions (critical for execution)
    find "$ROOTFS_DIR" -type f \( -name "ld-linux*.so.*" -o -name "ld64.so.*" -o -name "ld-*.so" \) | while read -r file; do
        chmod 755 "$file" || true
    done

    # Ensure penv scripts are executable
    chmod 755 "$ROOTFS_DIR/penv" || true
    find "$ROOTFS_DIR/penv" -type f -name "*.sh" -exec chmod 755 {} \; || true
    find "$ROOTFS_DIR/penv/startup.d" -type f -exec chmod 755 {} \; || true
    find "$ROOTFS_DIR/penv/cleanup.d" -type f -exec chmod 755 {} \; || true

    # Fix device directory permissions (if exists)
    if [ -d "$ROOTFS_DIR/dev" ]; then
        chmod 755 "$ROOTFS_DIR/dev"
    fi

    echo "Cleaning up..."
    export PENV_BUILD_STAGE="cleanup"
    if ! build::chroot; then
        echo "Error: Cleanup script failed" >&2
        return 1
    fi
    
    export PENV_BUILD_STAGE="test"
    # error if exit code is 2 (test failures)
    set +e
    build::chroot
    test_exit_code=$?
    if [ "$test_exit_code" -eq 2 ]; then
        echo "Error: Test script failed" >&2
        return 1
    elif [ "$test_exit_code" -eq 1 ]; then
        echo "Error: Test script finished with warnings" >&2
    fi
    set -e

    unset PENV_BUILD_STAGE
}