# OpenSoC Tier-1 — GitHub Setup Guide

Complete instructions for publishing the Level-1 public database to GitHub.
Covers account creation, GitHub CLI, export script, and future update workflow.

**Live repo:** https://github.com/siliconsethu/opensoc-soc1-l1

---

## Repository Strategy

| Repo | Visibility | Contents |
|------|-----------|---------|
| `siliconsethu/opensoc-soc1-l1` | **Public** | Level-1 RTL, TB, SW, scripts only |
| `siliconsethu/opensoc-soc1` | **Private** | Full database (all levels, docs, generators) |

Level-2 files (t1_xbar_32, t1_periph_ss_32, L2 firmware, coverage TB,
gen_*_doc.py) are never pushed to the public repo — the export script
enforces this automatically.

---

## Step 1 — Create GitHub Account

1. Open browser → **https://github.com/signup**
2. Enter:
   - **Username:** `siliconsethu`
   - **Email:** `hari.seshadri@gmail.com`
   - **Password:** (your choice)
3. Verify your email — GitHub sends a confirmation link
4. Choose the **Free** plan when prompted

---

## Step 2 — Install GitHub CLI

Open **PowerShell** (Start → PowerShell):

```powershell
winget install --id GitHub.cli --silent --accept-source-agreements --accept-package-agreements
```

Verify (open a new PowerShell window after install):

```powershell
gh --version
# Expected: gh version 2.x.x (...)
```

> **Note:** GitHub CLI installs to `C:\Program Files\GitHub CLI\`.
> It is available in PowerShell and CMD but not in Git Bash.
> Always use PowerShell for `gh` commands.

---

## Step 3 — Authenticate GitHub CLI

In PowerShell:

```powershell
gh auth login
```

Follow the prompts:

| Prompt | Select |
|--------|--------|
| Where do you use GitHub? | `GitHub.com` |
| Preferred protocol? | `HTTPS` |
| Authenticate Git with credentials? | `Y` |
| How to authenticate? | `Login with a web browser` |

The CLI prints an **8-character one-time code** (e.g. `ABCD-1234`).
Copy it, press Enter, and GitHub opens in your browser automatically.
Paste the code and click **Authorize github**.

Verify:
```powershell
gh auth status
# Expected: ✓ Logged in to github.com as siliconsethu
```

### Alternative: Personal Access Token (PAT)

If browser auth is blocked, use a PAT instead:

1. Go to **https://github.com/settings/tokens/new**
2. Note: `opensoc push`, Expiration: 90 days, Scope: **`repo`** (check top checkbox)
3. Click **Generate token** → copy the `ghp_...` token
4. In PowerShell:

```powershell
$env:GH_TOKEN = "ghp_your_token_here"
# Now gh commands work for this session
```

> **Security:** Never paste a PAT into a chat window or commit it to git.
> Revoke and regenerate at **https://github.com/settings/tokens** after use.

---

## Step 4 — Generate the Level-1 Export

From the repo root (Git Bash or PowerShell):

```bash
python scripts/export_l1_public.py
```

This creates `export/soc1_l1_public/` containing only the Level-1 public files:

| Category | Files included |
|----------|---------------|
| RTL | rv32i_iss, shakti_eclass_wrapper, t1_soc_top_eclass, t1_bus_l1, t1_sram_top_32, t1_periph_ss_l1, rtl/include/, vendor uart+gpio |
| Testbenches | t1_eclass_gpio_tb, t1_eclass_uart_tb, tb_level.svh |
| Software | crt0.S, eclass.ld, gpio_test.c, uart_test.c |
| Scripts | eclass_sim.py, build_sw.py, bin2hex.py |
| Docs | INSTALL.md, README_ECLASS.md, README_SIM.md, README_MAKEFILE.md, README_VENDOR_CHANGES.md, WINDOWS_QUICKSTART.md |
| Generated | README.md (public landing page), .gitignore, L1-only sw/Makefile, L1-only Makefile.questa |

**Dry run** (list files without copying):
```bash
python scripts/export_l1_public.py --dry-run
```

**Custom output directory:**
```bash
python scripts/export_l1_public.py --out /path/to/custom/dir
```

---

## Step 5 — Initialize Git and Commit

```bash
cd export/soc1_l1_public
git init
git config user.name "siliconsethu"
git config user.email "hari.seshadri@gmail.com"
git add .
git commit -m "Initial Level-1 public release"
git branch -M main
```

---

## Step 6 — Create GitHub Repo and Push

### Using GitHub CLI (PowerShell):

```powershell
gh repo create siliconsethu/opensoc-soc1-l1 `
  --public `
  --description "OpenSoC Tier-1 Shakti E-class RV32IM SoC — Level-1 public release (IIITDM Chennai)"
```

### Push (Git Bash or PowerShell):

```bash
git remote add origin https://github.com/siliconsethu/opensoc-soc1-l1.git
git push -u origin main
```

If prompted for credentials, use your GitHub username and PAT as the password.

---

## Step 7 — Verify

```powershell
gh repo view siliconsethu/opensoc-soc1-l1
```

Or open **https://github.com/siliconsethu/opensoc-soc1-l1** in your browser.

You should see:
- README.md rendered with badges
- 40 files in the correct directory tree
- Repository marked **Public**

---

## Token Security

| Action | When |
|--------|------|
| Revoke token at https://github.com/settings/tokens | Immediately after any session where you pasted a PAT into a terminal or chat |
| Generate a new token | Each time you need to push |
| Never commit a PAT | Check `.gitignore` includes no `.env` or credentials files |

---

## Future Updates — Publishing a New Release

When you update the Level-1 RTL or firmware and want to push to the public repo:

```bash
# 1. Re-run the export (wipes and recreates export/soc1_l1_public/)
python scripts/export_l1_public.py

# 2. Commit the changes
cd export/soc1_l1_public
git add .
git commit -m "Update: describe what changed"

# 3. Push (set token for this session if needed)
#    PowerShell:
#    $env:GH_TOKEN = "ghp_your_new_token"
git push
```

> The export directory `export/soc1_l1_public/` is a standalone git repo.
> Its `.git/` folder is separate from the main database — changes to the
> full database do not automatically propagate to the public repo.

---

## Troubleshooting

| Symptom | Cause | Fix |
|---------|-------|-----|
| `gh: command not found` in Git Bash | gh installs to Windows PATH, not Git Bash | Use PowerShell for all `gh` commands |
| `gh auth login` → `To get started... gh auth login` | Auth not persisted across shell sessions | Run `gh auth login` again in the same PowerShell window, or set `$env:GH_TOKEN` |
| `Repository not found` on push | Repo not created yet, or wrong URL | Run `gh repo create` first; verify URL with `git remote -v` |
| `Authentication failed` on push | Wrong credentials | Use PAT as password; username = `siliconsethu` |
| `remote origin already exists` | Remote already set | `git remote set-url origin <new-url>` |
| L2 files appear in export | Manifest out of date | Check `L1_FILES` list in `scripts/export_l1_public.py` |

---

## What the Public Repo Contains vs. Does Not Contain

### Included (Level-1 public)
- `t1_bus_l1.sv` — Level-1 AXI bus
- `t1_sram_top_32.sv` — 4 KB SRAM
- `t1_periph_ss_l1.sv` — OpenTitan UART + 16-bit GPIO
- `t1_soc_top_eclass.sv` — SoC top (LEVEL2 blocks inactive without define)
- `rv32i_iss.sv` — RV32IM instruction-set simulator
- Level-1 firmware: `gpio_test.c`, `uart_test.c`
- Level-1 testbenches: `t1_eclass_gpio_tb.sv`, `t1_eclass_uart_tb.sv`

### Not included (kept private)
- `t1_xbar_32.sv` — Level-2 crossbar
- `t1_boot_rom_32.sv` — Level-2 Boot ROM
- `t1_periph_ss_32.sv` — Level-2 peripheral subsystem (SPI/UART/GPIO)
- Level-2 firmware: `gpio_test_l2.c`, `uart_test_l2.c`
- Coverage TB: `t1_l2_cov_tb.sv`, `t1_l2_func_cov.sv`
- Document generators: `gen_swi_doc.py`, `gen_filelist_doc.py`, `gen_install_doc.py`
- Word documents: `docs/*.docx`

---

## Reference

| Resource | URL / Path |
|----------|-----------|
| Public repo | https://github.com/siliconsethu/opensoc-soc1-l1 |
| GitHub account settings | https://github.com/settings |
| Personal Access Tokens | https://github.com/settings/tokens |
| GitHub CLI docs | https://cli.github.com/manual |
| Export script | `scripts/export_l1_public.py` |
| Export output | `export/soc1_l1_public/` |
