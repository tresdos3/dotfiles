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
| `collect.sh` | Imports the 13 config entries into chezmoi safely (template-aware). |
| `bootstrap.sh` | Full setup: installs missing apps + tools, then pulls and applies your dotfiles. |
| `chezmoiignore` | Reference copy of the ignore list written by `collect.sh`. |
| `chezmoi.toml.example` | Example of the per-machine value (`email`) used by the templates. |
| `TEMPLATE_PATCHES.md` | The exact macOS → Linux replacements for the seeded `*.tmpl` files. |
| `LICENSE` | MIT License — free to use, modify and share. |

## How to run the `.sh` scripts

Open a terminal and change into this folder first:

```sh
cd ~/Documents/dotfiles-kit
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
| `install-rust.sh` | `--profile minimal\|default\|full`, `--modify-path`, `--force`, `--help` |

### GitHub authentication (HTTPS, no SSH)

`install-git.sh` sets:
- global name/email (it shows current values first — press ENTER to keep one),
- `commit.gpgsign false` globally, so commits never fail on a missing signing key,
- `credential.helper osxkeychain` on macOS, or `libsecret` on Linux (install the
  helper package if it isn't present).

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
On Linux, any supported package manager is enough.

Copy `bootstrap.sh` (or the whole kit) there, then:

```sh
chmod +x *.sh
./install-git.sh                    # install/configure git + HTTPS auth
./bootstrap.sh https://github.com/YOUR_USER/dotfiles-kit.git
# or, without Rust:
./bootstrap.sh --no-rust https://github.com/YOUR_USER/dotfiles-kit.git
```

`bootstrap.sh` clones the kit repo into `~/Documents/dotfiles-kit`, creates
`config/`, and writes `sourceDir = ".../config"` into
`~/.config/chezmoi/chezmoi.toml`. Set `KIT_DIR=/custom/path` to clone elsewhere.
Options: `--no-rust`, `-h` / `--help`. If you copy only `bootstrap.sh`, it still
installs chezmoi, fnm and Rust on its own.

The script:
1. detects the OS and package manager (Homebrew on macOS),
2. installs **only the missing packages** (already-installed apps are skipped),
3. installs chezmoi / fnm / Rust via the standalone installers when available,
4. clones the kit repo and writes `~/.config/chezmoi/chezmoi.toml`
   (`sourceDir` + email),
5. installs missing p10k / zsh plugins / pnpm / git-lfs,
6. shows `chezmoi diff`, asks before `chezmoi apply`.

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
