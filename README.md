# Oh My Zsh Configuration

This repository contains a personalized and optimized `.zshrc` configuration for Zsh. It's designed to be a powerful, free alternative to modern terminals like Warp, by leveraging the flexibility of Zsh, Oh My Zsh, and the Powerlevel10k theme.

## Preview

<img width="565" alt="image" src="https://github.com/user-attachments/assets/53b4d020-f72b-40a0-a8ce-c76a306138c8" />
<img width="564" alt="image" src="https://github.com/user-attachments/assets/bdecd75f-81be-4aa3-898a-78fc0f444a29" />
<img width="768" alt="image" src="https://github.com/user-attachments/assets/f93ba5b1-e78c-425b-a2d8-87120e9e80ec" />
<img width="764" alt="image" src="https://github.com/user-attachments/assets/4f8a7dc6-d2f3-4e40-8738-c885469fa7bc" />

## Features: A Warp-Like Experience, For Free

This configuration transforms your standard terminal into a modern, intelligent, and efficient workspace.

-   **Intelligent Autocompletion**:
    -   `zsh-autosuggestions` provides real-time, fish-like autosuggestions based on your command history.
    -   The advanced completion system offers smart, context-aware suggestions for commands, arguments, and paths.
-   **Syntax Highlighting**: `zsh-syntax-highlighting` colors commands as you type, helping you spot errors before you hit enter.
-   **Colorful `ls` Output**: Files, directories, and other file types are now distinctly colored for easy navigation, thanks to the new `LS_COLORS` configuration.
-   **Performance Optimized**: Blazing fast Zsh startup time with `POWERLEVEL9K_INSTANT_PROMPT`, so you're never waiting for your prompt.
-   **Rich Plugins**: A curated list of plugins enhances productivity without sacrificing performance.
    -   `git`, `docker`, `kubectl`, `pip`, `npm`: Essential tool integrations.
    -   `fzf`: A lightning-fast command-line fuzzy finder.
    -   `z`: Jump to your most used directories in an instant.
-   **Smart History**: Enhanced history with timestamps, deduplication, and sharing across sessions.
-   **Useful Aliases**: A rich set of aliases for common commands (`gs` for `git status -sb`, `..` for `cd ..`, etc.).
-   **Auto-Correction**: Automatically corrects typos in commands.

## Setup Guide

### 1. Prerequisites

-   A modern terminal application. [iTerm2](https://iterm2.com/) is recommended for macOS, but the default Terminal.app also works well.
-   [Homebrew](https://brew.sh/) for installing packages on macOS.

### 2. Installation

1.  **Install Oh My Zsh**:
    If you don't already have Oh My Zsh installed, run this command:
    ```bash
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    ```

2.  **Clone this Repository**:
    Clone this repository to a location on your local machine (e.g., `~/.oh-my-zsh-config`).
    ```bash
    git clone https://github.com/your-username/oh-my-zsh-configuration.git ~/.oh-my-zsh-config
    ```

3.  **Backup and Link `.zshrc`**:
    Backup your existing `.zshrc` and create a symbolic link to the one in this repository.
    ```bash
    mv ~/.zshrc ~/.zshrc.bak
    ln -s ~/.oh-my-zsh-config/.zshrc ~/.zshrc
    ```

4.  **Install Required Font**:
    Powerlevel10k uses a special font to render icons. The recommended one is MesloLGS NF.
    ```bash
    brew install --cask font-meslo-lg-nerd-font
    ```

### 3. Terminal Appearance & Configuration

1.  **Set the "Pro" Profile for Transparency (Optional)**:
    -   To achieve the semi-transparent terminal look shown in the previews, open `Terminal.app`.
    -   Go to `Preferences` → `Profiles` and set the `Pro` profile as your default. You can adjust the opacity and blur settings in this profile.

2.  **Set Terminal Font**:
    -   Open your terminal's preferences and select `MesloLGS NF` as your font. A font size of **10-12pt** is recommended for optimal viewing.
    -   **For Terminal.app**: `Preferences` → `Profiles` → `Text` → `Font` → `Change...`.
    -   **For iTerm2**: `Preferences` (`⌘ + ,`) → `Profiles` → `Text` → `Font` → `Change...`.

3.  **Configure Powerlevel10k**:
    -   The Powerlevel10k configuration wizard should start automatically. If not, run `p10k configure`.
    -   During the setup, when asked to choose a **"Prompt Connection"**, select **(3) No**. This disables the connecting lines between prompt segments and prevents a common resizing glitch.

4.  **Reload Your Configuration**:
    -   To apply the changes, you can either restart your terminal or run the following command to source the `.zshrc` file:
    ```bash
    source ~/.zshrc
    ```
    - Note: For some changes (especially deep shell integrations), a full restart with `exec zsh` or closing and reopening the terminal is the most reliable method.

## Known Issues

### Resizing Glitch

There is a known issue where resizing the terminal window horizontally can cause the prompt to misalign. This is largely mitigated by choosing not to have prompt connectors (`.`, `_`, or `/`) during the `p10k configure` setup.

## Uninstall

To revert to your previous configuration:

1.  **Remove the symbolic link:**
    ```bash
    rm ~/.zshrc
    ```
2.  **Restore your backup `.zshrc`:**
    ```bash
    mv ~/.zshrc.bak ~/.zshrc
    ```
3.  **(Optional) Remove the cloned repository:**
    ```bash
    rm -rf ~/.oh-my-zsh-config
    ```
4.  **Revert your terminal font** to your previous preference.
