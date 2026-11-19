# Template patches (macOS → Linux)

`collect.sh` created these files in the chezmoi source directory:

```
dot_zshrc.tmpl
dot_zprofile.tmpl
dot_wezterm.lua.tmpl
dot_gitconfig.tmpl
```

Each contains your original file plus a scaffold comment at the top. Below are
the exact replacements to make so the same files work on macOS and Linux.
Edit with `chezmoi edit ~/.zshrc` (etc.), then `chezmoi apply`.

## Useful template variables

| Expression | Value |
|---|---|
| `{{ .chezmoi.os }}` | `darwin` or `linux` |
| `{{ .chezmoi.homeDir }}` | `/Users/<user>` or `/home/<user>` |
| `{{ .email }}` | from `chezmoi.toml` |

---

## `dot_zshrc.tmpl`

**Android SDK (macOS path):**
```zsh
{{- if eq .chezmoi.os "darwin" }}
export ANDROID_HOME="$HOME/Library/Android/sdk"
export PATH="$PATH:$ANDROID_HOME/emulator:$ANDROID_HOME/platform-tools"
{{- end }}
```

**Powerlevel10k theme (Homebrew → local data dir):**
```zsh
{{- if eq .chezmoi.os "darwin" }}
source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh
{{- else }}
source "${XDG_DATA_HOME:-$HOME/.local/share}/powerlevel10k/powerlevel10k.zsh-theme"
{{- end }}
source ~/.p10k.zsh
```

**pnpm home (hardcoded → portable):**
```zsh
export PNPM_HOME="{{ .chezmoi.homeDir }}/Library/pnpm"
case ":$PATH:" in
  *":$PNPM_HOME/bin:"*) ;;
  *) export PATH="$PNPM_HOME/bin:$PATH" ;;
esac
```
On Linux, corepack may install pnpm elsewhere — adjust the Linux branch if needed.

**macOS-only blocks — wrap all of these in `{{- if eq .chezmoi.os "darwin" }} … {{- end }}`:**
- `.console-ninja/.bin` PATH line
- `Antigravity` / `Antigravity IDE` PATH lines
- `.spicetify` PATH line
- `export DYLD_LIBRARY_PATH="/opt/homebrew/opt/expat/lib:$DYLD_LIBRARY_PATH"`

**zsh plugins:**
```zsh
{{- if eq .chezmoi.os "darwin" }}
[[ -f /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -f /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
{{- else }}
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh" ]] && \
  source "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh"
[[ -f "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" ]] && \
  source "${XDG_DATA_HOME:-$HOME/.local/share}/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh"
{{- end }}
```

Everything else (aliases, `compinit`, fnm, cargo, p10k instant prompt) is portable — leave it.

---

## `dot_zprofile.tmpl`

Wrap the entire macOS-specific content:
```zsh
{{- if eq .chezmoi.os "darwin" }}
# Docker Desktop
export PATH="$PATH:{{ .chezmoi.homeDir }}/.docker/bin"
eval "$(/opt/homebrew/bin/brew shellenv)"
# JetBrains Toolbox
export PATH="$PATH:{{ .chezmoi.homeDir }}/Library/Application Support/JetBrains/Toolbox/scripts"
{{- end }}

. "{{ .chezmoi.homeDir }}/.local/bin/env"
```

---

## `dot_wezterm.lua.tmpl`

**Font fallback (Linux may not have JetBrains Mono installed):**
```lua
config.font = wezterm.font_with_fallback({
  "JetBrains Mono",
  "DejaVu Sans Mono",
})
```

**macOS blur — guard by target triple:**
```lua
if wezterm.target_triple:find("apple") then
  config.macos_window_background_blur = 20
end
```

Everything else (Tokyo Night, opacity, padding, OpenGL, scrollback, cursor,
fullscreen workaround) is portable.

---

## `dot_gitconfig.tmpl`

```gitconfig
[user]
	name = Your Name
	email = {{ .email }}
[core]
	excludesfile = {{ .chezmoi.homeDir }}/.gitignore_global
{{- if eq .chezmoi.os "darwin" }}
[difftool "sourcetree"]
	cmd = opendiff \"$LOCAL\" \"$REMOTE\"
[mergetool "sourcetree"]
	cmd = /Applications/Sourcetree.app/Contents/Resources/opendiff-w.sh \"$LOCAL\" \"$REMOTE\" -ancestor \"$BASE\" \"$MERGED\"
	trustExitCode = true
{{- end }}
[commit]
	template = {{ .chezmoi.homeDir }}/.stCommitMsg
[filter "lfs"]
	clean = git-lfs clean -- %f
	smudge = git-lfs smudge -- %f
	process = git-lfs filter-process
	required = true
[safe]
	directory = *
```

`gpgsign = false` is set explicitly in `[commit]` (and `signingkey` /
`gpg.format = ssh` are removed). This overrides any global signing setting so
commits never fail on a missing signing key. `install-git.sh` also disables
signing globally on new machines.

---

## After patching

```sh
chezmoi diff
chezmoi apply
chezmoi cd && git add -A && git commit -m "make configs cross-platform" && git push
```
