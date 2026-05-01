# ac - AI Commit

Fast commit message generation using AI models via opencode.

## Installation

```bash
cp commit.sh ~/.local/bin/ac
chmod +x ~/.local/bin/ac
source ~/.bashrc
```

## Usage

```bash
# Stage changes
git add .

# Generate and commit
ac

# Change model
ac --config
# or
ac -c
```

## Features

- Automatic model fetching from opencode API
- Interactive model selection on first run
- Support for custom model IDs
- Edit commit messages before committing
- Vi/Vim/Nano editor support (checks git config first)

## Models

View available models: https://opencode.ai/docs/zen/#models
