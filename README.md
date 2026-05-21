# Developer Workspace & Auto-Start Configuration

Welcome to your central workspace! This repository contains your utilities, scripts, and automation configurations for this Ubuntu server.

---

## 🚀 Configured Auto-Start Services (Systemd)

We have configured systemd **User Services with Linger**. This allows services to start automatically as the `developer` user immediately when the machine boots, **even if no user logs in**.

### 1. SSH Tunnel Service (Optional)
* **Script:** [ssh-tunnel.sh](../ssh-tunnel.sh) (Only generated if configured)
* **Service File:** `~/.config/systemd/user/ssh-tunnel.service` (Only generated if configured)
* **Goal:** Maintains a secure, passwordless local-to-remote SSH tunnel forwarding port `4000`.
* **Key Used:** `~/.ssh/id_ed25519`

> [!NOTE]
> **Optional Setup:**  
> This service is optional and can be skipped during the execution of `setup-new-server.sh`. If you choose to configure it, you must setup **passwordless SSH key-based authentication** for the background systemd daemon to function correctly without manual intervention on boot:
>
> 1. **Generate your SSH Key Pair** on the host server:
>    ```bash
>    ssh-keygen -t ed25519 -N "" -f ~/.ssh/id_ed25519
>    ```
> 2. **Copy your Public Key to the Remote Server**:
>    ```bash
>    ssh-copy-id -i ~/.ssh/id_ed25519.pub developer@192.168.249.129
>    ```
>    *(Replace `developer` and `192.168.249.129` with your target SSH server's username and IP).*
> 3. **Verify Passwordless Access**:
>    ```bash
>    ssh -i ~/.ssh/id_ed25519 developer@192.168.249.129
>    ```
>    If this logs you in instantly without prompting for a password, your configuration is successful!



### 2. Xiaoice OpenClaw API Service
* **Directory:** [xiaoice-openclaw-api](../xiaoice-openclaw-api)
* **Service File:** `~/.config/systemd/user/xiaoice-openclaw-api.service`
* **Goal:** Boots the docker-compose multi-container application automatically.

### 3. OpenClaw Character Dashboard Service
* **Directory:** [openclaw-character-dashboard](../openclaw-character-dashboard)
* **Service File:** `~/.config/systemd/user/openclaw-character-dashboard.service`
* **Goal:** Boots the character dashboard container environment automatically.

### 4. Claw3D Next.js Service
* **Directory:** [Claw3D](../Claw3D)
* **Service File:** `~/.config/systemd/user/claw3d.service`
* **Goal:** Runs the local Next.js node application in dev mode.

### 5. Domain Expansion AR Game Service
* **Directory:** [domain-expansion-ar-game](../amazon-nova-robotics/domain-expansion-ar-game)
* **Service File:** `~/.config/systemd/user/domain-expansion-ar-game.service`
* **Goal:** Boots the AR Game server Docker Compose environment automatically.

---

## 🌐 Server Port Allocation Map

Every running service is assigned to a distinct, non-overlapping port to prevent network conflicts:

| Service / App | Directory Path | Port | Protocol / Mode | Description |
| :--- | :--- | :--- | :--- | :--- |
| **Claw3D Next.js** | [Claw3D](../Claw3D) | **`3000`** | HTTP (Dev Server) | Local Next.js 3D Frontend |
| **Character Dashboard API** | [openclaw-character-dashboard](../openclaw-character-dashboard) | **`3001`** | HTTP / Express | Dashboard Resource/API Server |
| **Xiaoice OpenClaw API** | [xiaoice-openclaw-api](../xiaoice-openclaw-api) | **`3002`** | HTTP / Node.js | OpenClaw Bridge (Host Network Mode) |
| **Domain Expansion AR Game** | [domain-expansion-ar-game](../amazon-nova-robotics/domain-expansion-ar-game) | **`3443`** | HTTPS / Node.js | AR Game Server (Docker Port Mapped) |
| **SSH Port Forwarding** | [ssh-tunnel.sh](../ssh-tunnel.sh) | **`4000`** | TCP forwarding | Secure port tunneling to remote host |
| **Character Dashboard Client** | [openclaw-character-dashboard](../openclaw-character-dashboard) | **`5173`** | HTTP / Vite | Vite React Frontend Client |

---

## 🛠️ How to Manage Current Services

You can manage these services without `sudo` privileges using the `--user` flag:

| Action | SSH Tunnel | Xiaoice OpenClaw API | Character Dashboard | Claw3D Next.js | AR Game Server |
| :--- | :--- | :--- | :--- | :--- | :--- |
| **Check Status** | `systemctl --user status ssh-tunnel.service` | `systemctl --user status xiaoice-openclaw-api.service` | `systemctl --user status openclaw-character-dashboard.service` | `systemctl --user status claw3d.service` | `systemctl --user status domain-expansion-ar-game.service` |
| **Restart / Rebuild** | `systemctl --user restart ssh-tunnel.service` | `systemctl --user restart xiaoice-openclaw-api.service` | `systemctl --user restart openclaw-character-dashboard.service` | `systemctl --user restart claw3d.service` | `systemctl --user restart domain-expansion-ar-game.service` |
| **Stop / Shut Down** | `systemctl --user stop ssh-tunnel.service` | `systemctl --user stop xiaoice-openclaw-api.service` | `systemctl --user stop openclaw-character-dashboard.service` | `systemctl --user stop claw3d.service` | `systemctl --user stop domain-expansion-ar-game.service` |
| **Start / Boot Up** | `systemctl --user start ssh-tunnel.service` | `systemctl --user start xiaoice-openclaw-api.service` | `systemctl --user start openclaw-character-dashboard.service` | `systemctl --user start claw3d.service` | `systemctl --user start domain-expansion-ar-game.service` |
| **Disable Autostart** | `systemctl --user disable ssh-tunnel.service` | `systemctl --user disable xiaoice-openclaw-api.service` | `systemctl --user disable openclaw-character-dashboard.service` | `systemctl --user disable claw3d.service` | `systemctl --user disable domain-expansion-ar-game.service` |
| **View Live Logs** | `journalctl --user -u ssh-tunnel.service -f` | `journalctl --user -u xiaoice-openclaw-api.service -f` | `journalctl --user -u openclaw-character-dashboard.service -f` | `journalctl --user -u claw3d.service -f` | `journalctl --user -u domain-expansion-ar-game.service -f` |

---

## ➕ How to Add More Programs to Auto-Start

If you want to add more programs to start at boot under your user session:

### Step 1: Create Your Script
1. Save your script or program under your `Documents` folder (e.g., `my-script.sh`).
2. Make it executable:
   ```bash
   chmod +x ~/Documents/my-script.sh
   ```

### Step 2: Create a Systemd Service File
Create a new file in `~/.config/systemd/user/my-service.service`:
```ini
[Unit]
Description=My New Auto Start Service
After=network-online.target

[Service]
Type=simple
WorkingDirectory=%h/Documents
ExecStart=/usr/bin/bash %h/Documents/my-script.sh
Restart=on-failure
RestartSec=10

[Install]
WantedBy=default.target
```
> [!NOTE]
> `%h` in systemd unit files automatically resolves to the user's home directory.

### Step 3: Enable & Start It
Run the following commands to activate the service:
```bash
# Reload Systemd config
systemctl --user daemon-reload

# Enable it to run automatically on boot
systemctl --user enable my-service.service

# Start it immediately
systemctl --user start my-service.service
```

---

## 📁 Repository Contents

* [setup-new-server.sh](./setup-new-server.sh): Server bootstrap script to clone repositories and set up all auto-start services on a new machine.
* [README.md](./README.md): This workspace documentation hub.
