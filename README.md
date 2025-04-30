# SafeClean

![Shell Script](https://img.shields.io/badge/bash-4.0%2B-blue.svg)
![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)
![Status](https://img.shields.io/badge/status-stable-brightgreen.svg)

A reliable, secure, and customizable system cleanup script for Linux servers.

---

## 📦 Overview

**SafeClean** is a universal tool for **safe cleanup of Linux servers**. It removes unnecessary files, clears system logs, cache, temporary files, and old packages — **without risking system stability**.

The script performs analysis, warns about estimated cleanup volume, and gives you full control — simple, flexible, and safe.

---

## 🚀 Features

- 🧹 **Comprehensive cleanup**: Docker, systemd logs, APT, Snap, temp files
- 🔐 **Safe operation**: thorough checks and minimized risks
- 📊 **Detailed analysis** before execution
- 🛠️ **Flexible configuration**: config files, CLI flags, and interactive menu
- 🧪 **Test mode**: simulate cleanup without deleting anything
- 🔄 **Scheduler**: supports systemd timers and cron jobs
- 📝 **Syslog logging**, including JSON format
- ✅ **Built-in self-testing**

---

## 📚 How It Works

1. **Analyzes the system**: assesses logs, cache, Snap, Docker, and temp files.
2. **Displays a report** and estimated free space.
3. **Performs cleanup** — only after your confirmation or in `--force` mode.
4. Supports **simulation** via `--dry-run` or `--test-mode`.

---

## 🧠 When to Use It?

- When you're running out of disk space
- For regular server maintenance
- Before creating a backup
- Automatically on schedule (weekly/monthly)

---

## ⚙️ Installation

### 📥 Quick Install

```bash
bash <(wget -qO- https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

or

```bash
bash <(curl -s https://raw.githubusercontent.com/DigneZzZ/safe-clean-up/main/safeclean.sh) --install
```

### 🧰 Via Git

```bash
git clone https://github.com/DigneZzZ/safe-clean-up.git
cd safe-clean-up
chmod +x safeclean.sh
sudo ./safeclean.sh --install
```

---

## 🖥️ Usage Examples

```bash
safeclean --dry-run                 # Analyze without deleting
sudo safeclean --force             # Cleanup without confirmation
safeclean --config                 # Configure parameters manually
safeclean --schedule-systemd weekly  # Schedule weekly run
```

---

## 🔧 Configuration

Configuration can be defined via:
- CLI: `--journal-days 7`
- Interactive menu: `safeclean --config`
- Config file:
  - system-wide: `/etc/safeclean/config`
  - user-specific: `~/.config/safeclean/config`
  - custom: `--config-path /path/to/file`

### Example parameters:

| Parameter                 | Description                                       | Default     |
|--------------------------|---------------------------------------------------|-------------|
| `JOURNAL_DAYS`           | Retain systemd logs for N days                    | `10`        |
| `JOURNAL_SIZE`           | Max journal size in MB                            | `500`       |
| `DOCKER_KEEP_IMAGES`     | Preserve Docker images                            | `false`     |
| `TEMP_FILES_AGE`         | Delete temp files older than N days               | `1`         |
| `USE_SYSLOG`             | Log to syslog                                     | `false`     |
| `USE_JSON_LOG`           | Use JSON format for logs                          | `false`     |
| `CONFIRM_APT_AUTOREMOVE` | Ask for confirmation before apt autoremove        | `true`      |

---

## ⏱️ Scheduling

Supports both `systemd` and `cron`:

```bash
sudo safeclean --schedule-systemd daily   # With systemd timer
sudo safeclean --schedule weekly          # With cron
sudo safeclean --unschedule               # Remove scheduled jobs
```

---

## 🧪 Self-Testing

```bash
safeclean --self-test
```

---

## 🛡️ Security

- Root access check
- Safe handling of `/tmp`
- Accounts for open files
- All actions are logged
- Supports dry-run and test-mode
- Strict dependency validation

---

## ✅ Requirements

- Bash 4.0+
- Utilities: `find`, `du`, `df`, `lsof`, `bc`
- Optional: `systemd`, `logger`

---

## 🐧 Compatibility

- Ubuntu / Debian
- CentOS / RHEL
- Fedora
- Arch Linux
- openSUSE

---

## 📄 License

[MIT License](LICENSE)

---

## 🤝 Contributing

Pull requests are welcome!  
Report bugs, suggest improvements, and share your experience.

---

## 📚 Additional Resources

- 🌐 **Community Forum**: [openode.xyz](https://openode.xyz) — discussions on panels, scripts, and VPN setups.
- 📖 **Personal Blog**: [neonode.cc](https://neonode.cc) — technical notes, guides, and practical solutions.

### 💎 Premium Content

The forum [openode.xyz](https://openode.xyz) offers a **paid section** with access to:

- Detailed installation guides for **Remnawave**, **Marzban**, **3x-ui**, **X-UI**, and more.
- **Private SHM Club** — guides, configurations, and real-life use cases.
- Up-to-date scripts, automation tools, personal deployment and monetization experience.

👉 **Supporting the project via subscription** helps maintain high-quality and up-to-date content.

