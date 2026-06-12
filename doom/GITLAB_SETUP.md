# GitLab Integration Setup

This guide will help you set up the GitLab integration for Doom Emacs.

## 1. Set Environment Variables

**Important**: Since shell config files are typically in dotfiles repos, we keep sensitive values separate.

### For Fish shell (Recommended approach):

Create `~/.config/fish/conf.d/local.fish` (this file should NOT be in your dotfiles):

```fish
# ~/.config/fish/conf.d/local.fish
set -x GITLAB_URL "https://gitlab.com"
set -x GITLAB_PROJECT_ID "your-project-id-here"
set -x GITLAB_PROJECT_NAME "myproject"
set -x GITLAB_ISSUES_DIR "$HOME/notes/projects/myproject/issues"
```

**Then add to your fish dotfiles `.gitignore`:**
```gitignore
conf.d/local.fish
```

Fish automatically sources all files in `conf.d/` directory, so this will be loaded without modifying your tracked `config.fish`.

### For Zsh/Bash:

Create `~/.zshrc.local` or `~/.bashrc.local` (gitignored):

```bash
# ~/.zshrc.local
export GITLAB_URL="https://gitlab.com"
export GITLAB_PROJECT_ID="your-project-id-here"
export GITLAB_PROJECT_NAME="myproject"
export GITLAB_ISSUES_DIR="$HOME/notes/projects/myproject/issues"
```

**Then source it from your tracked config:**

Add to `~/.zshrc` or `~/.bashrc`:
```bash
# Load local machine-specific config (not in dotfiles)
[ -f ~/.zshrc.local ] && source ~/.zshrc.local
```

**And add to your shell dotfiles `.gitignore`:**
```gitignore
.zshrc.local
.bashrc.local
```

### Finding Your Project ID

1. Go to your GitLab project
2. Look in the project settings under **Settings > General**
3. You'll see **Project ID** near the top
4. It's a numeric ID like `12345678`

Alternatively, you can use the project path like `group/project-name`

## 2. Set Up GitLab Token

Create or update `~/.authinfo.gpg` with your GitLab token:

```
machine gitlab.com login api password YOUR_GITLAB_PERSONAL_ACCESS_TOKEN
```

### Creating a Personal Access Token

1. Go to GitLab: **User Settings > Access Tokens**
2. Create a new token with these scopes:
   - `api` (full API access)
   - `read_repository`
3. Copy the token (you'll only see it once!)
4. Add it to your `~/.authinfo.gpg` file

### For Company GitLab Instances

If using a company GitLab (e.g., `gitlab.company.com`):

```
machine gitlab.company.com login api password YOUR_COMPANY_GITLAB_TOKEN
```

Make sure `GITLAB_URL` matches: `export GITLAB_URL="https://gitlab.company.com"`

## 3. Reload Configuration

After setting environment variables:

1. Reload your shell: `source ~/.config/fish/config.fish` (or restart terminal)
2. Reload Doom Emacs: `SPC h r r`

## 4. Usage

### Keybindings

- `SPC o t` - Show GitLab Todos
- `SPC o g i` - Fetch and insert link to GitLab issue
- `SPC o g l` - Lookup and create org file for GitLab issue
- `SPC o g r` - Refresh current issue file from GitLab
- `SPC o g m` - Show GitLab Merge Requests

### Dashboard

You can also access GitLab Todos from the Doom dashboard (`SPC f p`).

## Troubleshooting

### "GITLAB_PROJECT_ID environment variable is not set"

Make sure you've:
1. Added the environment variables to your shell config
2. Reloaded your shell or restarted your terminal
3. Reloaded Doom Emacs

Test in terminal:
```bash
echo $GITLAB_PROJECT_ID
```

### "GitLab token not found in auth-source"

Make sure `~/.authinfo.gpg` exists and contains your token. The file should have this format:

```
machine gitlab.com login api password YOUR_TOKEN_HERE
```

You may need to encrypt it:
```bash
gpg -e -r your-email@example.com ~/.authinfo
```

## Multiple Projects

To work with multiple GitLab projects, add functions to your `~/.config/fish/conf.d/local.fish`:

```fish
# ~/.config/fish/conf.d/local.fish

# Default project (loaded on shell start)
set -x GITLAB_PROJECT_ID "12345"
set -x GITLAB_PROJECT_NAME "work-app"
set -x GITLAB_ISSUES_DIR "$HOME/notes/work/work-app/issues"

# Function to switch to different projects
function gitlab-personal
    set -x GITLAB_PROJECT_ID "67890"
    set -x GITLAB_PROJECT_NAME "myapp"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/personal/myapp/issues"
    echo "Switched to myapp GitLab project"
end

function gitlab-work
    set -x GITLAB_PROJECT_ID "12345"
    set -x GITLAB_PROJECT_NAME "work-app"
    set -x GITLAB_ISSUES_DIR "$HOME/notes/work/work-app/issues"
    echo "Switched to work-app GitLab project"
end
```

Then run `gitlab-work` or `gitlab-personal` before opening Emacs.

### Alternative: Use direnv

Install `direnv` and create `.envrc` files in each project directory:

```bash
# ~/work/project-a/.envrc
export GITLAB_PROJECT_ID="12345"
export GITLAB_PROJECT_NAME="project-a"
export GITLAB_ISSUES_DIR="$HOME/notes/work/project-a/issues"
```

direnv will automatically load the correct environment when you `cd` into that directory.
