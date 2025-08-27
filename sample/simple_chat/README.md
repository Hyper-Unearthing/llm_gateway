# Simple Chat

A text-based user interface (TUI) for chatting with AI models using the LLM Gateway library.

## Features

- **Two-Panel Layout**: Chat interface on the left, settings panel on the right
- **Multiple AI Models**: Support for Claude, OpenAI, and Groq models
- **Real-time Chat**: Interactive conversation with AI models
- **Model Switching**: Change models without restarting the application
- **Color-coded Messages**: Easy to distinguish between user, AI, and error messages

## Installation

1. Ensure you have the required gems installed:
   ```bash
   bundle install
   ```

2. Configure your API keys by editing the `.env` file:
   ```bash
   cp .env .env.local
   # Edit .env.local with your actual API keys
   ```

## Configuration

Set up your API keys and default model in the `.env` file:

```bash
# Claude API Key (for Claude models)
ANTHROPIC_API_KEY=your_ANTHROPIC_API_KEY_here

# OpenAI API Key (for GPT models)
OPENAI_API_KEY=your_openai_api_key_here

# Groq API Key (for Llama and Meta models)
GROQ_API_KEY=your_groq_api_key_here

# Default model to use on startup
DEFAULT_MODEL=claude-opus-4-20250514
```

## Usage

### Option 1: Using the bin script (Recommended)

From anywhere in the project:
```bash
bin/simple_chat
```

### Option 2: Direct execution

1. Navigate to the simple_chat directory:
   ```bash
   cd sample/simple_chat
   ```

2. Run the application:
   ```bash
   ruby run.rb
   ```

The application will automatically:
- Load your API keys from `.env`
- Start with your configured default model
- Launch the TUI interface

Start chatting immediately!

## Interface

### Left Panel - Chat
- **Message History**: Scrollable conversation history
- **Input Field**: Type your messages at the bottom
- **Color Coding**:
  - 🟢 Green: Your messages
  - 🔵 Blue: AI responses
  - 🔴 Red: Error messages

### Right Panel - Settings
- **Current Model**: Shows the active AI model
- **Model Dropdown**: Available models to switch between
- **Controls Help**: Keyboard shortcuts reference

## Keyboard Controls

| Key | Action |
|-----|--------|
| `Tab` | Toggle model selection dropdown |
| `↑` / `↓` | Navigate dropdown options |
| `Enter` | Select model or send message |
| `Backspace` | Delete input characters |
| `q` | Quit application |

## Supported Models

### Claude Models (Anthropic)
- Claude Opus 4 (claude-opus-4-20250514)
- Claude Sonnet 4 (claude-sonnet-4-20250514)
- Claude Opus 4.1 (claude-opus-4-1-20250805)
- Claude 3.5 Haiku (claude-3-5-haiku-20241022)

### OpenAI Models
- GPT-4 (gpt-4)
- GPT-3.5 Turbo (gpt-3.5-turbo)

### Groq Models
- **Llama Models (Meta)**:
  - Llama 3.1 8B Instant (llama-3.1-8b-instant)
  - Llama 3.3 70B Versatile (llama-3.3-70b-versatile)
  - Llama Guard 4 12B (meta-llama/llama-guard-4-12b)
- **OpenAI OSS Models**:
  - GPT OSS 120B (openai/gpt-oss-120b)
  - GPT OSS 20B (openai/gpt-oss-20b)

## Dependencies

- `curses` - Terminal control and interface
- `tty-box` - Drawing frames and panels
- `tty-screen` - Terminal size detection
- `tty-prompt` - Interactive prompts
- `llm_gateway` - AI model integration

## Architecture

- **simple_chat.rb**: Main TUI application class with panel rendering and input handling
- **chat_client.rb**: Simplified wrapper around LLM Gateway for direct chat functionality
- **run.rb**: Entry point with configuration setup and application launcher

## Error Handling

The application handles common errors gracefully:
- Invalid API keys
- Network connectivity issues
- Model unavailability
- Malformed responses

Errors are displayed in red in the chat panel and don't crash the application.

## Development

To extend the application:
1. Add new models to the `@available_models` array in `simple_chat.rb`
2. Modify the chat client in `chat_client.rb` for custom message processing
3. Adjust the UI layout by modifying the panel drawing methods

## License

This project follows the same license as the parent LLM Gateway project.
