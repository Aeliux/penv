# build.sh - Functions to build and set up a root filesystem

readonly PENV_VERSION="2"
readonly PENV_BUILD_TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

export PENV_ENV_MODE="build"

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
    local temp_script="/tmp/penv_${script_name}_$$"
    
    if [ ! -f "$script_path" ]; then
        echo "Error: Script not found: $script_path" >&2
        return 1
    fi
    
    echo "Executing $script_name in chroot..."
    mkdir -p "$ROOTFS_DIR/tmp"
    
    # Copy script to temp location
    if ! cp "$script_path" "$ROOTFS_DIR$temp_script"; then
        echo "Error: Failed to copy script to chroot" >&2
        return 1
    fi
    
    chmod +x "$ROOTFS_DIR$temp_script"
    
    # Execute in chroot and capture result
    local exit_code=0
    if ! chroot "$ROOTFS_DIR" /bin/sh "$temp_script"; then
        exit_code=$?
        echo "Error: Script execution failed with exit code $exit_code" >&2
    fi
    
    # Clean up
    rm -f "$ROOTFS_DIR$temp_script"
    
    return $exit_code
}

# Main setup function
build::setup() {
    if [ "$#" -ne 0 ]; then
        echo "Usage: build::setup" >&2
        return 1
    fi
    
    local script_dir
    script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
    
    # Create penv directory structure
    _create_directories \
        penv \
        penv/metadata \
        penv/startup.d \
        penv/cleanup.d
    
    # Write metadata
    _write_metadata
    
    # Apply overrides to rootfs recursively
    echo "Applying overrides..."
    cp -a "$script_dir/build/overrides/." "$ROOTFS_DIR"/
    
    # Set up root user
    echo "Setting up root user..."
    cp -a "$script_dir/build/overrides/etc/skel/." "$ROOTFS_DIR"/root/
    
    # Copy startup script
    cp "$script_dir/build/core/startup.sh" "$ROOTFS_DIR"/penv/startup.sh
    
    # copy hooks
    cp "$script_dir/build/universal/prepare.sh" "$ROOTFS_DIR"/penv/startup.d/00-prepare.sh
    cp "$script_dir/build/universal/cleanup.sh" "$ROOTFS_DIR"/penv/cleanup.d/90-cleanup.sh
    cp "$script_dir/build/universal/basic-cleanup.sh" "$ROOTFS_DIR"/penv/cleanup.d/99-basic-cleanup.sh

    # Apply universal patches
    build::chroot_script "$script_dir/build/universal/patch.sh"
    
    echo "Penv ${PENV_VERSION} setup completed successfully"
}

# Finalizr function
build::finalize() {
    # Remove device files
    echo "Removing device files..."
    find "$ROOTFS_DIR/dev" -type c -o -type b 2>/dev/null | xargs rm -f 2>/dev/null || true

    # Fix permissions for proot compatibility
    echo "Setting permissions..."
    # Ensure critical directories have proper permissions
    chmod 755 "$ROOTFS_DIR" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/bin" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/usr" "$ROOTFS_DIR/usr/bin" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/sbin" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/lib" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/etc" 2>/dev/null || true
    chmod 1777 "$ROOTFS_DIR/tmp" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/var" 2>/dev/null || true
    chmod 755 "$ROOTFS_DIR/opt" 2>/dev/null || true

    # Fix /root directory permissions
    if [ -d "$ROOTFS_DIR/root" ]; then
        chmod 700 "$ROOTFS_DIR/root"
    fi

    # Ensure all executables in bin directories are executable
    find "$ROOTFS_DIR/bin" "$ROOTFS_DIR/sbin" "$ROOTFS_DIR/usr/bin" "$ROOTFS_DIR/usr/sbin" \
        -type f -executable 2>/dev/null | while read -r file; do
        chmod 755 "$file" 2>/dev/null || true
    done

    # Fix library permissions
    find "$ROOTFS_DIR/lib" "$ROOTFS_DIR/usr/lib" -type f -name "*.so*" 2>/dev/null | while read -r file; do
        chmod 644 "$file" 2>/dev/null || true
    done

    # Fix dynamic linker permissions (critical for execution)
    find "$ROOTFS_DIR" -type f \( -name "ld-linux*.so.*" -o -name "ld64.so.*" -o -name "ld-*.so" \) 2>/dev/null | while read -r file; do
        chmod 755 "$file" 2>/dev/null || true
    done

    # Ensure penv scripts are executable
    chmod 755 "$ROOTFS_DIR/penv" 2>/dev/null || true
    find "$ROOTFS_DIR/penv" -type f -name "*.sh" -exec chmod 755 {} \; 2>/dev/null || true
    find "$ROOTFS_DIR/penv/startup.d" -type f -exec chmod 755 {} \; 2>/dev/null || true
    find "$ROOTFS_DIR/penv/cleanup.d" -type f -exec chmod 755 {} \; 2>/dev/null || true

    # Fix device directory permissions (if exists)
    if [ -d "$ROOTFS_DIR/dev" ]; then
        chmod 755 "$ROOTFS_DIR/dev"
    fi

    echo "Cleaning up..."
    build::chroot_script "$script_dir/build/universal/cleanup.sh"
}