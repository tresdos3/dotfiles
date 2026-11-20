# Dotfiles kit

Everything needed to move your shell / terminal / editor configuration between
machines using [chezmoi](https://www.chezmoi.io/).

**All scripts work on both macOS and Linux.** On Linux they use your distro
package manager (apt / dnf / pacman / zypper / apk); on macOS they use Homebrew
(except `collect.sh`, which only needs chezmoi). Authentication is **HTTPS +
Personal Access Token** — no SSH keys are used or configured anywhere.

## Files in this folder

| File | Purpose |
|---|---|
| `install-git.sh` | Installs git if missing; asks for name/email and configures git globally; sets HTTPS credential helper. |
| `install-chezmoi.sh` | Installs/upgrades chezmoi. Skips if already installed. |
| `install-fnm.sh` | Installs/upgrades fnm (Node version manager). Skips if already installed. |
| `install-rust.sh` | Installs/upgrades Rust via rustup. Skips if already installed. |
| `git-sync.sh` | Pull → auto-commit → push a git repo over HTTPS. |
| `collect.sh` | Imports the 12 config entries into chezmoi safely (template-aware). |
| `bootstrap.sh` | Full setup with interactive selection of apps/tools and dotfiles, then pull + apply. |
| `chezmoiignore` | Reference copy of the ignore list written by `collect.sh`. |
| `chezmoi.toml.example` | Example of the per-machine value (`email`) used by the templates. |
| `TEMPLATE_PATCHES.md` | The exact macOS → Linux replacements for the seeded `*.tmpl` files. |
| `LICENSE` | MIT License — free to use, modify and share. |

## How to run the `.sh` scripts

Open a terminal and change into this folder first:

```sh
cd ~/Documents/dotfiles-kit   # or wherever this repo lives, e.g. ~/Documents/dotfiles
```

Make the scripts executable **once** (after copying the folder or re-creating a
script):

```sh
chmod +x *.sh
```

Then run any script with `./` in front of its name:

```sh
./install-git.sh
./install-chezmoi.sh
./install-fnm.sh
./install-rust.sh
./collect.sh --dry-run
./git-sync.sh --dry-run
./bootstrap.sh https://github.com/YOUR_USER/dotfiles.git
```

If you get `permission denied`, run `chmod +x *.sh` again. You can also always
run a script through bash without changing permissions:

```sh
bash install-git.sh
bash collect.sh --dry-run
```

To see available options, pass `--help`:

```sh
./install-git.sh --help
./bootstrap.sh --help
./git-sync.sh --help
```

> Run the scripts from a normal terminal (not inside an editor). `install-git.sh`
> and `bootstrap.sh` ask questions interactively.

## Standalone installers (macOS + Linux)

Each installer is idempotent: if the tool is already installed, installation is
skipped.

```sh
./install-git.sh                 # install git if missing, then configure identity/auth
./install-chezmoi.sh             # Homebrew on macOS, official binary on Linux
./install-fnm.sh                 # Homebrew on macOS, binary on Linux
./install-rust.sh                # rustup, stable + minimal profile
```

| Script | Options |
|---|---|
| `install-git.sh` | `--no-auth` (skip credential helper), `--help` |
| `install-chezmoi.sh` | `--brew`, `--pkg` (Linux), `--script`, `--dir PATH`, `--force`, `--help` |
| `install-fnm.sh` | `--dir PATH` (Linux), `--no-brew` (force binary on macOS), `--force`, `--help` |
| `install-rust.sh` | `--force`, `--help` (plain `curl … \| sh` via rustup, default profile) |

### GitHub authentication (HTTPS, no SSH)

`install-git.sh` sets:
- global name/email (it shows current values first — press ENTER to keep one),
- `commit.gpgsign false` globally, so commits never fail on a missing signing key,
- `credential.helper osxkeychain` on macOS, or `oauth` on Linux (install
  `git-credential-oauth` with apt), falling back to `libsecret`.

Then create a **Personal Access Token**:
GitHub → Settings → Developer settings → Personal access tokens → Tokens (classic)
→ enable the `repo` scope → copy it. On your first HTTPS push, paste the token
as the password. The credential helper stores it, so you won't be asked again.

## Part 1 — On the source machine (this Mac)

### 1. Install git and chezmoi, then point chezmoi at the kit's config folder

```sh
./install-git.sh
./install-chezmoi.sh
mkdir -p config
```

Create (or edit) `~/.config/chezmoi/chezmoi.toml` and add:

```toml
sourceDir = "/Users/YOUR_USER/Documents/dotfiles-kit/config"
```

The collected data **always lives in `~/Documents/dotfiles-kit/config`**, which is
inside this repo. Do not run plain `chezmoi init` — it would create its own
source directory elsewhere (and could create a nested `.git` inside `config/`).
This repo is the single source of truth for both scripts and dotfiles.

### 2. Create the private GitHub repo

- New repository named `dotfiles`, **Private**, empty (no README/license).
- Use HTTPS for all remote URLs: `https://github.com/YOUR_USER/dotfiles.git`.

### 3. Collect the files

```sh
./collect.sh --dry-run     # preview
./collect.sh               # do it
```

`collect.sh`:
- adds 12 entries (zsh, zprofile, p10k, wezterm, gitconfig, nvim,
  gitignore_global, hgignore_global, stCommitMsg, ghostty, warp, fish). Zed is
  **not** collected,
- writes `.chezmoiignore` (secrets, caches, histories, backups excluded),
- converts 4 files into templates and seeds a scaffold comment in each,
- copies itself into `config/scripts/collect.sh` so it syncs with the repo.
- flags: `--dry-run` (preview), `--force` (re-add templates, with `*.bak.TIMESTAMP`
  backups). Templates are never overwritten on a normal re-run; raw files are.
- refuses to run if chezmoi's source dir is not this repo's `config/` folder.

### 4. Edit the templates

Open each seeded template and follow `TEMPLATE_PATCHES.md`:

```sh
chezmoi edit ~/.zshrc
chezmoi edit ~/.zprofile
chezmoi edit ~/.wezterm.lua
chezmoi edit ~/.gitconfig
```

### 5. Push

```sh
chezmoi diff
chezmoi apply
chezmoi cd
git remote add origin https://github.com/YOUR_USER/dotfiles.git
git add -A && git commit -m "Initial dotfiles" && git push -u origin main
```

Or from that directory: `../git-sync.sh` (copy `git-sync.sh` next to it first).

## Part 2 — On the other machine (Linux or macOS)

**Requirements:** on macOS, Homebrew must be installed (https://brew.sh).
On Linux, any supported package manager is enough. On Ubuntu/Debian, WezTerm is
installed from the official `apt.fury.io/wez` repository, which `bootstrap.sh`
adds automatically when you select the WezTerm component.

Copy `bootstrap.sh` (or the whole kit) there, then:

```sh
chmod +x *.sh
./install-git.sh                    # install/configure git + HTTPS auth
./bootstrap.sh https://github.com/YOUR_USER/dotfiles.git
# accept every menu default without prompts:
./bootstrap.sh --yes https://github.com/YOUR_USER/dotfiles.git
# keep the old behaviour of skipping Rust:
./bootstrap.sh --no-rust https://github.com/YOUR_USER/dotfiles.git
```

### Choosing what to install

`bootstrap.sh` shows **two interactive checklists before installing anything**.
Press ENTER for the shown default, `y`/`n` to toggle one item, `a` for all,
`x` for none.

1. **Components to install**

   | Component | Default | How it is installed |
   |---|---|---|
   | zsh | on | package manager |
   | Git LFS | on | package manager + `git lfs install` |
   | Neovim | on | package manager |
   | fish | on | package manager |
   | WezTerm | on | **apt.fury.io repo → apt** on Ubuntu/Debian, cask on macOS |
   | JetBrains Mono font | on | package manager (skipped if already installed) |
   | fnm + Node + pnpm | on | fnm installer, Node LTS, corepack |
   | powerlevel10k | on | git clone |
   | zsh plugins | on | git clone ×2 |
   | Rust | on | plain `curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \| sh` |
   | Git credential helper | on | `git-credential-oauth` (or libsecret) |
   | uv | off | package manager |
   | Ghostty | off | package manager |

2. **Dotfiles to apply** — the selection is passed to `chezmoi diff` and
   `chezmoi apply` as explicit targets, so unselected files are never touched.

   | Group | Targets |
   |---|---|
   | zsh | `~/.zshrc`, `~/.zprofile`, `~/.p10k.zsh` |
   | git | `~/.gitconfig`, `~/.gitignore_global`, `~/.hgignore_global`, `~/.stCommitMsg` |
   | WezTerm | `~/.wezterm.lua` |
   | Neovim | `~/.config/nvim` |
   | Ghostty | `~/.config/ghostty` |
   | fish | `~/.config/fish` |
   | Warp | `~/.warp` (macOS only — warned about on Linux) |

`--yes` accepts every default, `--no-rust` forces the Rust component off, and
`-h` / `--help` shows usage. `collect.sh` is deliberately **not** involved in
selection — it keeps working exactly as before on macOS.

### Repo location

`bootstrap.sh` reuses the checkout it lives in when that folder already has
`config/` and `.git/` (so this repo can stay at `~/Documents/dotfiles`). When run
from a standalone copy, it clones into `~/Documents/dotfiles-kit`. Set
`KIT_DIR=/custom/path` to override. It writes `sourceDir = ".../config"` and
`[data] email` into `~/.config/chezmoi/chezmoi.toml`.

The script then:
1. detects the OS and package manager,
2. adds the WezTerm apt repo (Ubuntu/Debian) when selected,
3. installs **only the selected packages that are missing**,
4. installs chezmoi (always), then the selected tools,
5. clones (or reuses) the repo and writes the chezmoi config,
6. shows `chezmoi diff` for the selected dotfiles, asks, then applies them.

Then open `nvim` once to bootstrap LazyVim plugins, and you're done.

## Auto push/pull with git-sync.sh

Run it inside any git repo (or pass a path). It pulls with rebase, commits any
local changes with a timestamp message, then pushes over HTTPS:

```sh
./git-sync.sh                                  # current directory's repo
./git-sync.sh ~/Documents/dotfiles-kit
./git-sync.sh -m "update zsh config"
./git-sync.sh --dry-run                        # preview only
```

If the repo has no `origin`, no commits, or a pull conflict, it stops with a
clear message. It never force-pushes.

For a fresh repo:

```sh
cd ~/Documents/dotfiles-kit
git init
git remote add origin https://github.com/YOUR_USER/dotfiles.git
./git-sync.sh                                  # first push sets upstream
```

## Everyday workflow

On either machine:

```sh
./collect.sh                   # re-import raw file changes into ./config
chezmoi diff
chezmoi apply
chezmoi edit ~/.zshrc          # edit a managed file (in ./config)
./git-sync.sh                  # pull + commit + push scripts AND dotfiles together
```

## Safety notes

- **Never commit secrets.** `.chezmoiignore` excludes SSH/GPG keys, tokens,
  OAuth files, histories, caches and backup files. Keep it that way.
- The kit's `.gitignore` blocks keys, tokens, `.env` and local `chezmoi.toml`.
  `chezmoi.toml.example` is intentionally allowed.
- `chezmoi apply` overwrites target files in `$HOME` — always run `chezmoi diff`
  first, especially on a machine that already has configs.
- The repo is private. Authentication uses a PAT + credential helper per
  machine; no SSH keys are generated or stored by these scripts.

## License

MIT — free for personal and commercial use, modification and distribution.
See [LICENSE](LICENSE).
