# OpenClaw Backup & Recovery Suite (Configs & Agent Blueprints)

A robust, production-grade automated backup and restore suite tailored for the **OpenClaw** agentic framework. This suite is designed to capture **configurations, agent blueprints, custom skills, and workspace structures**, while explicitly **excluding** session databases, conversations history/diaries, and process logs to keep backups lightweight, fast, and secure.

---

## 📂 Backup & Exclude Scopes

To ensure agent configuration states can be completely restored without copying heavy, stale runtime data, we enforce a strict file division:

### Included in Blueprints Backup
- **Main Config:** `/home/developer/.openclaw/openclaw.json` (models, providers, channels, bindings)
- **Agent Identity & Keys:** `/home/developer/.openclaw/identity/` and `/home/developer/.openclaw/credentials/`
- **Agent Workspace Layouts:** `/home/developer/.openclaw/workspace/` root files:
  - `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `USER.md`, `TOOLS.md`, `HEARTBEAT.md`
- **Sub-Agent Directories & Code:** All sub-agent folders (e.g. `robot_1/`, `robot_2/`, `communication-manager/`) including files:
  - `AGENTS.md`, `SOUL.md`, `IDENTITY.md`, `TOOLS.md`, `USER.md`, `HEARTBEAT.md`, `requirements.txt`, `run.sh`

### Excluded (Memory and Runtime Data)
- **SQLite Databases:** `*.sqlite`, `*.sqlite-shm`, `*.sqlite-wal` (conversations and runtime states)
- **Conversational Diaries:** All `memory/` folders (e.g. `/workspace/memory/*.md` or `workspace/robot_1/memory/*.md`) containing logs of previous conversations
- **Process Logs:** `/home/developer/.openclaw/logs/*`
- **Temporary Files:** `/home/developer/.openclaw/exec-approvals.json`, update checks, and handoffs

---

## 🛠️ Components List

The backup suite consists of 5 files in this directory:

1. **[`backup.conf`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/backup.conf):** Configuration file containing paths, exclusions, retention limits, and optional GPG encryption options.
2. **[`backup.sh`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/backup.sh):** The main backup script that parses configurations, archives files using custom tar settings, sets secure file permissions (`chmod 600`), and prunes older archives.
3. **[`restore.sh`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/restore.sh):** Interactive recovery script. Lists available backups, creates a **safety rollback copy** of current settings before extracting, and cleanly restores the config.
4. **[`git-sync-blueprints.sh`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/git-sync-blueprints.sh):** Keeps an elegant version history of your agent markdown configurations. Configures `.gitignore` exclusions and commits workspace blueprint changes automatically.
5. **[`setup.sh`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/setup.sh):** Setup wizard. Automates cron job configuration and tests execution.

---

## 🚀 Getting Started

### 1. Configure Settings
Open [`backup.conf`](file:///home/developer/.gemini/antigravity-cli/scratch/openclaw-backups/backup.conf) to review paths and retention settings. By default, it saves archives to `/home/developer/openclaw-backup-archives/` and prunes archives older than `14` days.

### 2. Run Setup Wizard
To install automatic backup schedules, run:
```bash
./setup.sh
```
This adds two jobs to your user `crontab`:
- **`backup.sh`** runs daily at 2:00 AM (stores compressed blueprints and credentials).
- **`git-sync-blueprints.sh`** runs daily at 11:30 PM (commits blueprint shifts to the local Git repository).

### 3. Manual Backup Execution
You can manually run a backup anytime:
```bash
./backup.sh
```

---

## 🔄 Restoration & Rollbacks

In the event of system corruption or when syncing to a new machine, restore configurations effortlessly.

### Running Interactive Restore
Run without arguments to list available backups and select one:
```bash
./restore.sh
```

### Safety Features
- **Auto-Rollback Preservation:** Before applying any backup, `restore.sh` creates a full copy of your current active setups in `/tmp/openclaw_rollback_before_restore_TIMESTAMP`. If extraction fails, it automatically recovers your current active setup so you never get locked out.

---

## 🔒 Security Practices

Because `openclaw.json` contains highly sensitive credentials (Telegram bot tokens, API keys), follow these security rules:
1. **Restrict Archive Access:** The `backup.sh` script automatically sets archive file permissions to owner-only read-write (`chmod 600`). Never modify this behavior.
2. **Enable GPG Encryption:** If you plan on moving archives offsite (e.g. cloud/NAS backups), set `ENCRYPT_BACKUPS=true` in `backup.conf` and configure a passphrase to securely encrypt all output packages.
