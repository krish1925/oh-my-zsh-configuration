ZSH CONFIG — READ ME FIRST
==========================

TO INSTALL
  1. Double-click  "Install Zsh Config".
  2. A Terminal window opens and walks you through it. Answer the questions
     (Enter accepts the default). It takes 5–15 minutes on a fresh Mac.

IF macOS SAYS IT "CANNOT VERIFY THE DEVELOPER"
  This app is not signed with an Apple Developer ID. Right-click (or Control-click)
  "Install Zsh Config" → Open → Open.   Or: System Settings → Privacy & Security →
  scroll down → "Open Anyway".

WHAT YOU GET
  • Fast zsh with autosuggestions, syntax colouring, fuzzy history and completion
  • Command palette (Ctrl+G) and cheat sheet (zhelp)
  • A private AI assistant that runs on THIS Mac only:
        ? <what you want>    writes the command onto your prompt (never runs it)
        ?? <question>        answers, with read-only tools
        ??? <question>       slower, deeper reasoning model

OPTIONAL: THE DECISION MODEL (not installed by this app)
  A small extra model can make /remember replace outdated facts, double-check risky
  commands and text before it goes to a cloud service. It is about 8 GB and built from source, so
  it is left out. Everything works without it; the features simply stay quiet.
  Details: ~/.config/zsh/agent/decide_spec.json and  ai-winnow status.

REQUIREMENTS
  macOS 13+, internet during setup. The AI needs Apple Silicon (M1 or newer);
  16 GB RAM or more is recommended, 24 GB for the deep model.
  The AI model (about 5.5 GB) is only downloaded if you say yes.

IT IS SAFE TO TRY
  Your current ~/.zshrc, ~/.p10k.zsh and ~/.config/zsh are backed up to
  ~/.zsh-config-backup/ before anything changes. Your ~/.zshrc.local, shell
  history and Ghostty config are never overwritten.

TO UNDO
  In Terminal:   zsh ~/.config/zsh/uninstall.sh
  This restores what you had before. Nothing is deleted; Zsh Config's files are
  moved into ~/.zsh-config-backup/removed-<time>/.

YOUR OWN SETTINGS GO IN  ~/.zshrc.local  — it is never touched by the installer.
