# Doom Emacs Configuration

My personal Doom Emacs configuration with GitLab integration, org-mode workflows, and custom dashboard.

## Quick Start

### 1. Clone and Install

```bash
cd ~/.config/doom
# Files are already here from your dotfiles
```

### 2. Set Up Local Environment (Required!)

Create `~/.config/fish/conf.d/local.fish` (this file is gitignored in your fish dotfiles):

```fish
# GitLab Configuration
set -x GITLAB_URL "https://gitlab.com"
set -x GITLAB_PROJECT_ID "your-project-id"
set -x GITLAB_PROJECT_NAME "myproject"
set -x GITLAB_ISSUES_DIR "$HOME/notes/projects/myproject/issues"
```

**Important**: Add `conf.d/local.fish` to your fish dotfiles `.gitignore`!

### 3. Set Up GitLab Token

Create or update `~/.authinfo.gpg`:

```
machine gitlab.com login api password YOUR_GITLAB_TOKEN
```

### 4. Reload Doom

```bash
doom sync
doom reload  # or SPC h r r in Emacs
```

## Features

### Dashboard Menu Items
- Recently opened files
- Reload last session
- Open org-agenda
- **Show Org Directory** - Browse your notes
- **Show GitLab Todos** - View GitLab todos
- Jump to bookmark
- Open private configuration
- Open documentation

### GitLab Integration

**Keybindings:**
- `SPC o t` - Show GitLab Todos
- `SPC o g i` - Fetch GitLab issue (insert link)
- `SPC o g l` - Lookup GitLab issue (create org file)
- `SPC o g r` - Refresh current issue
- `SPC o g m` - Show GitLab merge requests

**GitLab Todos Buffer:**
- `d` / `RET` - Toggle todo done/pending
- `r` / `gr` - Refresh
- `a` - Show all pending
- `c` - Show completed
- `i` - Filter issues only
- `m` - Filter merge requests only
- `q` - Quit

### Other Keybindings
- `SPC o d` - Open org directory
- `SPC o v` - Toggle vterm
- `SPC o T` - Toggle vterm (alternate)
- `C-c t` - Toggle vterm (original)

## File Structure

```
.
├── README.md              # This file
├── GITLAB_SETUP.md        # Detailed GitLab setup guide
├── env.fish.example       # Example environment variables
├── .gitignore             # Gitignore for this directory
├── config.el              # Main Doom configuration
├── init.el                # Doom modules
├── packages.el            # Package declarations
├── custom.el              # Emacs custom settings
├── dashboard.el           # Dashboard customizations
├── gitlab.el              # GitLab integration
└── org-agenda.el          # Org-mode and agenda config
```

## Multiple Projects

To work with multiple GitLab projects, create functions in your `~/.config/fish/conf.d/local.fish`:

```fish
function gitlab-work
    set -x GITLAB_PROJECT_ID "12345"
    set -x GITLAB_PROJECT_NAME "work-app"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/work/work-app/issues"
    echo "Switched to work-app"
end

function gitlab-personal
    set -x GITLAB_PROJECT_ID "67890"
    set -x GITLAB_PROJECT_NAME "myapp"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/personal/myapp/issues"
    echo "Switched to myapp"
end
```

Then run `gitlab-work` or `gitlab-personal` before opening Emacs.

## Troubleshooting

See [GITLAB_SETUP.md](./GITLAB_SETUP.md) for detailed setup instructions and troubleshooting.

### Common Issues

**"GITLAB_PROJECT_ID environment variable is not set"**

This happens when Emacs can't access your shell environment variables.

**Quick fix:**
1. Make sure `~/.config/fish/conf.d/local.fish` exists with your variables
2. **Restart Emacs** (don't just reload config - fully quit and reopen)
3. If launched from GUI (Spotlight/Dock), Emacs needs to import from shell

**Verify it works:**
- In terminal: `echo $GITLAB_PROJECT_ID` (should show your ID)
- In Emacs: `M-: (getenv "GITLAB_PROJECT_ID")` (should show same ID)

**Why this happens:**
- Terminal Emacs: ✅ Inherits shell environment automatically
- GUI Emacs (macOS): ❌ Doesn't run your shell, needs `exec-path-from-shell`

**Solution (already configured):**
The `config.el` includes this fix:
```elisp
(exec-path-from-shell-copy-envs
 '("GITLAB_URL" "GITLAB_PROJECT_ID" "GITLAB_PROJECT_NAME" "GITLAB_ISSUES_DIR"))
```

This imports variables from your default shell into Emacs.

**"GitLab token not found in auth-source"**
- Check that `~/.authinfo.gpg` exists with your token
- Format: `machine gitlab.com login api password YOUR_TOKEN`

## Contributing

This is my personal config, but feel free to fork and adapt for your needs!

## License

MIT
