# Setup Checklist for New Machine

Quick checklist when setting up this Doom config on a new machine.

## ✅ Prerequisites

- [ ] Doom Emacs installed
- [ ] Dotfiles cloned (includes this config)

## ✅ Configuration Steps

### 1. Add to Fish Dotfiles `.gitignore`

```bash
# In your fish dotfiles repo (e.g., ~/dotfiles/fish/.gitignore or ~/.config/fish/.gitignore)
echo "conf.d/local.fish" >> .gitignore
git add .gitignore
git commit -m "Ignore local machine-specific fish config"
```

### 2. Create Local Environment Config

```bash
# Create the local config file (NOT tracked in dotfiles)
touch ~/.config/fish/conf.d/local.fish
```

**Edit `~/.config/fish/conf.d/local.fish`** with your project details:

```fish
# GitLab Configuration
set -x GITLAB_URL "https://gitlab.com"
set -x GITLAB_PROJECT_ID "YOUR_PROJECT_ID"
set -x GITLAB_PROJECT_NAME "myproject"
set -x GITLAB_ISSUES_DIR "$HOME/notes/projects/myproject/issues"
```

Find your project ID:
- Go to GitLab project → Settings → General
- Copy the numeric Project ID

### 3. Set Up GitLab Token

Create/edit `~/.authinfo.gpg`:

```bash
# Option 1: Direct edit (will be encrypted by GPG)
echo "machine gitlab.com login api password YOUR_GITLAB_TOKEN" >> ~/.authinfo

# Option 2: Use Emacs to edit encrypted file
emacs ~/.authinfo.gpg
```

Add this line:
```
machine gitlab.com login api password YOUR_GITLAB_TOKEN
```

Get your token:
- GitLab → User Settings → Access Tokens
- Create token with `api` scope
- Copy the token (shown only once!)

### 4. Reload Everything

```bash
# Reload fish shell
source ~/.config/fish/config.fish

# Verify environment variables are set in shell
echo $GITLAB_PROJECT_ID

# Sync Doom
doom sync
```

### 5. **IMPORTANT: Fully Restart Emacs**

```bash
# Don't just reload - QUIT and relaunch Emacs completely
# This is necessary for exec-path-from-shell to import your environment
```

**Why?** When you launch Emacs from macOS GUI (Spotlight/Dock), it doesn't have access to your Fish shell environment. The config uses `exec-path-from-shell` to import variables, but this only happens at startup.

### 6. Verify Environment in Emacs

After restarting Emacs, verify variables are loaded:

```elisp
M-: (getenv "GITLAB_PROJECT_ID")
```

Should return your project ID. If it returns `nil`, see troubleshooting below.

### 7. Test It Works

- `SPC o t` - Should show GitLab todos
- `SPC o g l 123` - Should create issue file

If you get "GITLAB_PROJECT_ID environment variable is not set":
1. Check `~/.config/fish/conf.d/local.fish` exists
2. Verify in terminal: `echo $GITLAB_PROJECT_ID`
3. **Fully quit and restart Emacs** (not just reload)
4. Check in Emacs: `M-: (getenv "GITLAB_PROJECT_ID")`

## ✅ Optional: Multiple Projects

If you work on multiple projects, add functions to `~/.config/fish/conf.d/local.fish`:

```fish
function gitlab-work
    set -x GITLAB_PROJECT_ID "12345"
    set -x GITLAB_PROJECT_NAME "work-app"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/work/work-app/issues"
    echo "→ Switched to work-app"
end

function gitlab-personal
    set -x GITLAB_PROJECT_ID "67890"
    set -x GITLAB_PROJECT_NAME "myapp"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/personal/myapp/issues"
    echo "→ Switched to myapp"
end
```

Then just run `gitlab-work` or `gitlab-personal` before opening Emacs.

## ✅ Done!

Your Doom Emacs with GitLab integration is ready to use! 🎉

See [README.md](./README.md) for features and keybindings.
