# Oh My Zsh Configuration

This repository contains a personalized and optimized `.zshrc` configuration for Zsh. It's designed to be a powerful, free alternative to modern terminals like Warp, by leveraging the flexibility of Zsh, Oh My Zsh, and the Powerlevel10k theme.

## Preview

<img width="565" alt="image" src="https://github.com/user-attachments/assets/53b4d020-f72b-40a0-a8ce-c76a306138c8" />
<img width="564" alt="image" src="https://github.com/user-attachments/assets/bdecd75f-81be-4aa3-898a-78fc0f444a29" />
<img width="768" alt="image" src="https://github.com/user-attachments/assets/f93ba5b1-e78c-425b-a2d8-87120e9e80ec" />
<img width="764" alt="image" src="https://github.com/user-attachments/assets/4f8a7dc6-d2f3-4e40-8738-c885469fa7bc" />

## Features: A Warp-Like Experience, For Free

This configuration transforms your standard terminal into a modern, intelligent, and efficient workspace with extensive functionality.

### 🚀 Performance & Speed
- **Blazing Fast Startup**: Optimized with `POWERLEVEL9K_INSTANT_PROMPT` and lazy loading for sub-100ms startup times
- **Smart Completion Caching**: Intelligent completion system with caching for faster responses
- **Optimized Plugin Loading**: Carefully selected plugins that enhance productivity without sacrificing speed
- **Efficient History Management**: 1M+ command history with smart deduplication and instant search

### 🎨 Visual Excellence
- **Modern Powerlevel10k Theme**: Beautiful, informative prompt with Git integration and status indicators
- **Syntax Highlighting**: Real-time command coloring with `zsh-syntax-highlighting`
- **Colorful File Listings**: Enhanced `ls` output with distinct colors for different file types
- **Rich Unicode Support**: Full support for icons and symbols (requires proper font configuration)

### 🤖 Intelligent Features
- **Fish-like Autosuggestions**: Real-time suggestions based on history with `zsh-autosuggestions`
- **Smart Auto-correction**: Automatic typo correction for commands
- **Context-aware Completion**: Advanced completion for commands, paths, and arguments
- **Fuzzy Finding**: Integrated `fzf` for lightning-fast file and directory navigation

### 🛠 Developer Tools Integration
- **Git Workflow**: Comprehensive Git aliases and functions with visual branch switching
- **Docker & Kubernetes**: Built-in completion and shortcuts for containerized workflows
- **Python & Node.js**: Lazy-loaded `conda` and `nvm` for optimal performance
- **Package Managers**: Support for `pip`, `npm`, `brew`, and more

### 📁 Enhanced Navigation
- **Smart Directory Jumping**: `z` plugin for frecency-based directory navigation
- **Directory Bookmarks**: Custom bookmark system for instant directory access
- **History Navigation**: Arrow key history search and `ALT+LEFT/RIGHT` for directory history
- **Auto-completion**: Tab completion for paths, commands, and Git branches

### 🎯 Productivity Boosters
- **Rich Alias Collection**: 50+ carefully crafted aliases for common tasks
- **Custom Functions**: Advanced functions for Git workflow, file management, and system tasks
- **Quick Notes**: Built-in note-taking system with timestamps
- **Archive Extraction**: Universal `extract` function for any archive format
- **History Management**: Backup, cleaning, and search functions for command history

## Setup Guide

### 1. Prerequisites

- A modern terminal application:
  - **macOS**: [iTerm2](https://iterm2.com/) (recommended) or Terminal.app
  - **Linux**: GNOME Terminal, Konsole, or Alacritty
  - **Windows**: Windows Terminal or WSL2
- **Package Manager**:
  - macOS: [Homebrew](https://brew.sh/)
  - Linux: Your distribution's package manager
- **Git**: For cloning the repository

### 2. Installation

1. **Install Oh My Zsh**:
   If you don't already have Oh My Zsh installed:
   ```bash
   sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
   ```

2. **Install Required Plugins**:
   ```bash
   # zsh-autosuggestions
   git clone https://github.com/zsh-users/zsh-autosuggestions ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-autosuggestions
   
   # zsh-syntax-highlighting
   git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
   
   # Powerlevel10k theme
   git clone --depth=1 https://github.com/romkatv/powerlevel10k.git ${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k
   ```

3. **Clone this Repository**:
   ```bash
   git clone https://github.com/your-username/oh-my-zsh-configuration.git ~/.oh-my-zsh-config
   ```

4. **Backup and Link Configuration**:
   ```bash
   # Backup existing configuration
   mv ~/.zshrc ~/.zshrc.bak
   
   # Link to the new configuration
   ln -s ~/.oh-my-zsh-config/.zshrc ~/.zshrc
   ```

### 3. Font Configuration (CRITICAL)

**⚠️ Important**: The default terminal fonts **will not display icons correctly**. You must install and configure a Nerd Font.

1. **Install Nerd Font**:
   ```bash
   # macOS with Homebrew
   brew install font-meslo-lg-nerd-font
   
   # Or download manually from: https://github.com/ryanoasis/nerd-fonts
   ```

2. **Alternative Recommended Fonts**:
   - **MesloLGS NF** (Recommended for Powerlevel10k)
   - **Hack Nerd Font**
   - **JetBrains Mono Nerd Font**
   - **Fira Code Nerd Font**

3. **Configure Terminal Font**:
   - **Terminal.app**: `Preferences` → `Profiles` → `Text` → `Font` → Select "MesloLGS NF"
   - **iTerm2**: `Preferences` → `Profiles` → `Text` → `Font` → Select "MesloLGS NF"
   - **VS Code Terminal**: Add to settings.json:
     ```json
     "terminal.integrated.fontFamily": "MesloLGS NF"
     ```

### 4. Powerlevel10k Configuration

1. **Run Configuration Wizard**:
   ```bash
   p10k configure
   ```

2. **Important Configuration Choices**:
   - **Font Installation**: If prompted, answer **Yes** to install MesloLGS NF
   - **Character Display**: Make sure all Unicode characters display correctly
   - **Prompt Style**: Choose your preferred style (Lean, Classic, or Rainbow)
   - **Character Set**: Select **Unicode** (not ASCII) for full icon support
   - **Prompt Connection**: Choose **(3) No** to prevent resizing glitches
   - **Prompt Height**: Choose **(1) Compact** for better performance

3. **Verify Icon Display**:
   After configuration, you should see:
   - Git branch icons (e.g., )
   - Folder icons (e.g., 📁)
   - Status symbols (e.g., ✓, ✗, ⚡)

### 5. Terminal Appearance (Optional)

1. **Enable Transparency** (macOS Terminal.app):
   - Go to `Preferences` → `Profiles`
   - Select or create the "Pro" profile
   - Adjust opacity and blur settings
   - Set as default profile

2. **Color Scheme Recommendations**:
   - **Dracula** (included in most terminals)
   - **One Dark**
   - **Solarized Dark**

### 6. Additional Tools (Optional but Recommended)

```bash
# Enhanced file operations
brew install fd bat tree htop

# Git tools
brew install git-delta # Better git diff
brew install lazygit   # Terminal UI for git

# Modern Unix tools
brew install ripgrep exa zoxide
```

## Key Features Explained

### Smart Functions

- **`mkcd <dir>`**: Create directory and cd into it
- **`fcd`**: Fuzzy find and cd to directory
- **`fbr`**: Fuzzy Git branch switcher with preview
- **`gcmsg`**: Smart Git commit with file analysis
- **`hist`**: Fuzzy search command history
- **`bookmark <name>`**: Bookmark current directory
- **`jump [name]`**: Jump to bookmarked directory
- **`note [text]`**: Quick note-taking system
- **`extract <file>`**: Universal archive extractor

### Enhanced Git Workflow

```bash
# Quick status and operations
gs          # git status (short format)
ga .        # git add all
gcmsg       # smart commit with auto-generated message
gp          # git push
gl          # beautiful git log

# Branch management
fbr         # fuzzy branch switcher
gcb feature # create and checkout new branch
gf          # fetch all remotes and prune
```

### Productivity Aliases

```bash
# Navigation
ll          # detailed file listing
..          # go up one directory
...         # go up two directories
ltr         # list files by time (recent first)

# System shortcuts
h           # history
j           # jobs
path        # show PATH variable
now         # current time
week        # current week number
```

## Troubleshooting

### Font Issues

**Problem**: Icons appear as squares or question marks
**Solution**: 
1. Ensure you've installed a Nerd Font
2. Configure your terminal to use the Nerd Font
3. Run `p10k configure` and select Unicode character set

### Performance Issues

**Problem**: Slow terminal startup
**Solution**:
1. The configuration includes lazy loading for heavy tools
2. Disable unused plugins in the `plugins` array
3. Check for conflicting shell configurations

### Resizing Glitch

**Problem**: Prompt misaligns when resizing terminal horizontally
**Solution**: 
1. During `p10k configure`, choose "No" for prompt connectors
2. The configuration already includes settings to minimize this issue

### Git Integration Not Working

**Problem**: Git status not showing in prompt
**Solution**:
1. Ensure you're in a Git repository
2. Check Git configuration: `git config --list`
3. Re-run `p10k configure`

## Customization

### Adding Your Own Aliases

Create `~/.zshrc.local` for personal customizations:

```bash
# Personal aliases
alias myproject='cd ~/Projects/my-important-project'
alias serve='python -m http.server 8000'

# Custom functions
deploy() {
  echo "Deploying to production..."
  # Your deployment commands
}
```

### Environment-Specific Settings

The configuration automatically loads `~/.zshrc.local` if it exists, allowing you to:
- Add work-specific aliases
- Configure company-specific tools
- Override default settings

## Uninstall

To revert to your previous configuration:

1. **Remove the symbolic link**:
   ```bash
   rm ~/.zshrc
   ```

2. **Restore your backup**:
   ```bash
   mv ~/.zshrc.bak ~/.zshrc
   ```

3. **Remove cloned repository** (optional):
   ```bash
   rm -rf ~/.oh-my-zsh-config
   ```

4. **Revert terminal font** to your previous preference

## Contributing

Feel free to:
- Report issues or bugs
- Suggest new features or improvements
- Submit pull requests with enhancements
- Share your customizations
