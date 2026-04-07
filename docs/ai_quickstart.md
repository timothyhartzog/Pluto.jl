# AI Features Quickstart

Pluto supports AI-assisted analysis through external language model (LLM) providers.
This guide covers everything you need to start your first AI-assisted notebook in minutes.

## Prerequisites

- Julia 1.10 or later
- Pluto 0.20 or later (`import Pkg; Pkg.add("Pluto")`)
- An API key for at least one supported AI provider

## Supported Providers

| Provider | Environment Variable | Notes |
|----------|---------------------|-------|
| OpenAI (GPT-4o, GPT-4, GPT-3.5) | `OPENAI_API_KEY` | Most widely tested |
| Anthropic (Claude 3.x) | `ANTHROPIC_API_KEY` | Strong reasoning |
| Mistral | `MISTRAL_API_KEY` | Open-weight option |
| Ollama (local) | *(none – runs locally)* | No key required; private by default |

## Step 1 – Set Your API Key

Set the key **before** starting Pluto so that it is available to notebook processes.

### macOS / Linux (bash/zsh)

```bash
export OPENAI_API_KEY="sk-..."
julia -e 'import Pluto; Pluto.run()'
```

### Windows (PowerShell)

```powershell
$env:OPENAI_API_KEY = "sk-..."
julia -e 'import Pluto; Pluto.run()'
```

### Persistent configuration (all platforms)

Add the export line to your shell profile (`~/.bashrc`, `~/.zshrc`, etc.) or create a
`.env` file in your project directory and load it with the `DotEnv` package inside
Pluto:

```julia
# In a Pluto cell
import DotEnv
DotEnv.config()   # reads .env from the current directory
```

> **Security tip:** Never hard-code API keys directly in notebook cells.
> Use environment variables or a secrets manager so that keys are not
> accidentally committed to version control or shared with collaborators.

## Step 2 – Open the Quickstart Notebook

From the Pluto home screen, open `sample/AI Quickstart.jl`.
The notebook guides you through verifying your provider credentials and running
a first prompt.

## Step 3 – Run a First Prompt

Inside the quickstart notebook, a single cell sends a test prompt to your
configured provider:

```julia
using HTTP, JSON3

response = HTTP.post(
    "https://api.openai.com/v1/chat/completions",
    ["Authorization" => "Bearer $(ENV["OPENAI_API_KEY"])",
     "Content-Type"  => "application/json"],
    JSON3.write(Dict(
        "model"    => "gpt-4o-mini",
        "messages" => [Dict("role" => "user", "content" => "Hello from Pluto!")],
    ))
)

JSON3.read(response.body)["choices"][1]["message"]["content"]
```

A successful response confirms your credentials are working.

## Safety and Privacy Guidance

- **Data minimisation:** Only send the data necessary for the task.
  Avoid uploading personally identifiable information (PII) or confidential
  datasets to third-party APIs without explicit permission and appropriate
  data-processing agreements.
- **Local providers:** For sensitive data, consider a locally hosted model
  via [Ollama](https://ollama.com/) (`ollama serve`) so that data never leaves
  your machine.
- **Audit outputs:** AI-generated code and analysis can contain errors or
  hallucinations. Always review and validate results before acting on them.
- **Rate limits and costs:** Monitor your API usage dashboard.
  Sending large datasets in prompts can lead to unexpected costs.
- **Reproducibility:** AI responses are non-deterministic.
  For reproducible notebooks, cache responses or store the AI output as
  a static variable after your first run.

## Next Steps

- Follow the end-to-end example in `sample/AI Guided Example.jl`
  (import → clean → analyze → export).
- Read the [Troubleshooting Guide](ai_troubleshooting.md) if you hit errors.
