# SafeClean

A robust, secure, and configurable system cleanup script for Linux servers.

[Русская версия (Russian version)](README_RU.md)

## Overview

SafeClean is a comprehensive system cleanup tool designed specifically for Linux servers. It safely removes unnecessary files, cleans up system logs, and frees disk space while maintaining system stability and security.

## Features

- **Comprehensive Cleanup**: Cleans Docker resources, systemd journals, APT cache, Snap revisions, and temporary files
- **Safe Operation**: Performs thorough checks before deletion and avoids removing critical files
- **Detailed Analysis**: Provides estimates of reclaimable space before performing any actions
- **Flexible Scheduling**: Supports both systemd timers and traditional cron jobs
- **Configurable**: Customizable thresholds and behavior through command-line options or interactive menu
- **Logging**: Optional syslog integration with JSON format support
- **Test Mode**: Simulates cleanup operations without making actual changes
- **Self-Testing**: Built-in self-test functionality to verify script integrity

## Installation

### Quick Installation (One-liner)

```bash
bash <(wget -qO- https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

Or with curl:

```bash
bash <(curl -s https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

### Manual Installation

```bash
# Download the script
wget https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh

# Make it executable
chmod +x safeclean.sh

# Install it system-wide
sudo ./safeclean.sh --install
```

### From Repository

```bash
git clone https://github.com/DigneZzZ/safe-clean-up.git
cd safe-clean-up
chmod +x safeclean.sh
sudo ./safeclean.sh --install
```

## Usage

### Basic Usage

```bash
# Show help
safeclean --help

# Analyze system without cleaning (dry run)
safeclean --dry-run

# Clean with confirmation prompts
safeclean

# Clean without confirmation (requires root)
sudo safeclean --force
```

### Advanced Options

```bash
# Configure settings through interactive menu
safeclean --config

# Use custom configuration file
safeclean --config-path /path/to/config

# Set specific journal retention
safeclean --journal-days 7 --journal-size 300

# Keep Docker images during cleanup
safeclean --keep-docker-images

# Enable syslog with JSON format
safeclean --syslog --json-log

# Test mode (shows commands without executing them)
safeclean --test-mode
```

### Scheduling

```bash
# Schedule with systemd timer (recommended for modern systems)
sudo safeclean --schedule-systemd daily

# Schedule with traditional cron
sudo safeclean --schedule weekly

# Remove all scheduled tasks
sudo safeclean --unschedule
```

## Configuration

SafeClean can be configured through command-line options, an interactive menu, or configuration files.

### Default Configuration Locations

- System-wide: `/etc/safeclean/config`
- User-specific: `~/.config/safeclean/config`

### Configuration Parameters

- `JOURNAL_DAYS`: Number of days to keep systemd journal logs (default: 10)
- `JOURNAL_SIZE`: Maximum size of systemd journal in MB (default: 500)
- `DOCKER_KEEP_IMAGES`: Whether to preserve Docker images during cleanup (default: false)
- `TEMP_FILES_AGE`: Age in days of temporary files to delete (default: 1)
- `USE_SYSLOG`: Enable logging to syslog (default: false)
- `USE_JSON_LOG`: Use JSON format for syslog entries (default: false)
- `CONFIRM_APT_AUTOREMOVE`: Prompt for confirmation before apt autoremove (default: true)

## Security Features

- Root permission checks for sensitive operations
- Safe handling of temporary files
- Verification of open files before deletion
- Dependency checking before execution
- Comprehensive error handling and logging

## Requirements

- Bash 4.0 or higher
- Core utilities: find, du, df, lsof, bc
- Optional: systemd (for timer functionality)
- Optional: logger (for syslog integration)

## Compatibility

SafeClean is designed to work on most Linux distributions, with specific support for:

- Ubuntu/Debian
- CentOS/RHEL
- Fedora
- Arch Linux
- openSUSE

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.
