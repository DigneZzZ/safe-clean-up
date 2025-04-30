# 🧹 SafeClean [![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE) [![Shell](https://img.shields.io/badge/Script-Bash-green.svg)](https://www.gnu.org/software/bash/) [![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)](#)

A reliable and customizable cleanup script for Linux systems.

---

## ⚙️ Features

- 🧼 **Comprehensive cleanup**: Docker resources, systemd journals, APT cache, Snap revisions, and `/tmp`
- 🔒 **Safe execution**: Avoids deleting critical files and checks for necessary permissions
- 📊 **Pre-cleanup analysis**: Estimates disk space to be freed before executing
- 🕒 **Flexible scheduling**: Supports both `systemd` timers and traditional `cron` jobs
- 🧩 **Highly configurable**: Customize behavior via CLI flags, config files, or interactive menu
- 📝 **Logging support**: Optional `syslog` logging with JSON format
- 🧪 **Dry-run mode**: Simulates cleanup actions without making any changes
- 🔍 **Self-test**: Built-in integrity and functionality test

---

## 🚀 Quick Installation

Using `wget`:

```bash
bash <(wget -qO- https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

Using `curl`:

```bash
bash <(curl -s https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

From repository:

```bash
git clone https://github.com/DigneZzZ/safe-clean-up.git
cd safe-clean-up
chmod +x safeclean.sh
sudo ./safeclean.sh --install
```

---

## 📌 Basic Usage

```bash
safeclean --help           # Show help message
safeclean --dry-run        # Analyze without making changes
sudo safeclean             # Run cleanup with confirmation
sudo safeclean --force     # Run cleanup without prompts
```

---

## 🛠️ Advanced Options

```bash
safeclean --config                   # Launch interactive config menu
safeclean --journal-days 7          # Retain logs for N days
safeclean --journal-size 300        # Limit journal size to N MB
safeclean --keep-docker-images      # Preserve Docker images
safeclean --syslog --json-log       # Enable syslog with JSON format
safeclean --test-mode               # Simulate cleanup actions
```

---

## ⏱️ Scheduling

```bash
# Using systemd (recommended)
sudo safeclean --schedule-systemd daily

# Using cron
sudo safeclean --schedule weekly

# Remove all scheduled jobs
sudo safeclean --unschedule
```

---

## ⚙️ Configuration

The script can be configured via CLI, an interactive menu, or config files.

### Default config file paths:

- **System-wide**: `/etc/safeclean/config`
- **User-specific**: `~/.config/safeclean/config`

### Example config parameters:

```ini
JOURNAL_DAYS=10
JOURNAL_SIZE=500
DOCKER_KEEP_IMAGES=false
TEMP_FILES_AGE=1
USE_SYSLOG=true
USE_JSON_LOG=true
CONFIRM_APT_AUTOREMOVE=true
```

---

## 🔐 Safety

- Verifies root access when required
- Avoids deleting critical or open files
- Checks dependencies before running
- Logs all errors and actions
- Integrated self-test functionality

---

## ✅ Compatibility

Designed for most Linux distributions, with tested support for:

- Ubuntu / Debian
- CentOS / RHEL
- Fedora
- Arch Linux
- openSUSE

**Requires:** `bash >= 4.0`, `find`, `du`, `df`, `lsof`, `bc`  
**Optional:** `systemd`, `logger`

---

## 🧪 Self-Test

Run internal diagnostics and validation checks:

```bash
safeclean --self-test
```

---

## 📄 License

This project is licensed under the [MIT License](LICENSE).

---

## 🤝 Contributing

Contributions are welcome! Feel free to open pull requests or issues. Please ensure your code is tested and matches the project’s style.
```
