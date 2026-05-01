# ac - AI Commit

Fast commit message generation using AI models via OpenRouter.

## Installation

```bash
cp commit.sh ~/.local/bin/ac
chmod +x ~/.local/bin/ac
source ~/.bashrc
```

## Setup

1. Get your OpenRouter API key: https://openrouter.ai/keys
2. Set the environment variable:
   ```bash
   export OPENROUTER_API_KEY=your_key_here
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

- Automatic model fetching from OpenRouter API
- Uses free models by default (`openrouter/free`)
- Interactive model selection on first run
- Support for custom model IDs
- Edit commit messages before committing
- Vi/Vim/Nano editor support (checks git config first)
- Benchmark script to test model speeds

## Scripts

- **commit.sh**: Core script - generates and commits with AI
- **list-models.sh**: List available models
  - `./list-models.sh` - Show all free models
  - `./list-models.sh -f` - Filter only free models
  - `./list-models.sh -n` - Space-separated model names
- **benchmark.sh**: Test model response times
  - `./benchmark.sh model1 model2 model3` - Benchmark specific models

## Available Models

View available free models:
```bash
./list-models.sh --free
```

Or online: https://openrouter.ai/docs/models

## Default Model

- **`openrouter/free`** - Uses OpenRouter's free tier (rotates through available free models)
- Custom models: Use their full ID from OpenRouter (e.g., `mistral-7b-instruct-free`)

## Commit Message Format

Generated messages are single words (lowercase):
- `fix` - Bug fixes
- `feat` - New features
- `docs` - Documentation
- `refactor` - Code refactoring
- `test` - Tests
- `chores` - Maintenance
- `init` - Initial commit
- `update` - Updates
