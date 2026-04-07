### A Pluto.jl notebook ###
# v0.20.24

using Markdown
using InteractiveUtils

# ╔═╡ a1b2c3d4-0001-11ea-0000-000000000001
md"""
# 🤖 AI Features Quickstart

Welcome!  This notebook walks you through **setting up an AI provider** and sending
your first prompt from a Pluto notebook.

**What you need:**
- A supported AI provider API key **or** a local Ollama installation
- The `HTTP` and `JSON3` packages (Pluto will install them automatically)

> 📖 For full setup instructions and safety guidance see
> [`docs/ai_quickstart.md`](../docs/ai_quickstart.md).
"""

# ╔═╡ a1b2c3d4-0002-11ea-0000-000000000001
md"""
## Step 1 – Check Your API Key

The cell below reads your API key from the environment.
Set it **before** starting Pluto:

```bash
# macOS / Linux
export OPENAI_API_KEY="sk-..."
julia -e 'import Pluto; Pluto.run()'
```

```powershell
# Windows PowerShell
$env:OPENAI_API_KEY = "sk-..."
julia -e 'import Pluto; Pluto.run()'
```

> 🔒 **Privacy tip:** Never paste your key directly into a notebook cell.
> Use environment variables so the key is not accidentally saved or shared.
"""

# ╔═╡ a1b2c3d4-0003-11ea-0000-000000000001
api_key_status = let
	key = get(ENV, "OPENAI_API_KEY", "")
	if isempty(key)
		md"⚠️ **`OPENAI_API_KEY` is not set.** Please set it and restart Pluto."
	else
		md"✅ **`OPENAI_API_KEY` is set** ($(length(key)) characters). Ready to go!"
	end
end

# ╔═╡ a1b2c3d4-0004-11ea-0000-000000000001
md"""
## Step 2 – Install Required Packages

Pluto's package manager handles this automatically. The first run may take a
minute to download `HTTP` and `JSON3`.
"""

# ╔═╡ a1b2c3d4-0005-11ea-0000-000000000001
begin
	import Pkg
	Pkg.add(["HTTP", "JSON3"])
end

# ╔═╡ a1b2c3d4-0006-11ea-0000-000000000001
begin
	using HTTP
	using JSON3
end

# ╔═╡ a1b2c3d4-0007-11ea-0000-000000000001
md"""
## Step 3 – Choose Your Provider

Edit the cell below to select your provider.  Supported options:

| Value | Provider |
|-------|----------|
| `"openai"` | OpenAI (GPT-4o / GPT-4 / GPT-3.5) |
| `"anthropic"` | Anthropic Claude |
| `"ollama"` | Local Ollama (no key required) |
"""

# ╔═╡ a1b2c3d4-0008-11ea-0000-000000000001
provider = "openai"   # ← change me

# ╔═╡ a1b2c3d4-0009-11ea-0000-000000000001
md"""
## Step 4 – Send a Test Prompt

The helper below sends a single message to the chosen provider and returns the
model's reply as a `String`.

> **Error: Assignment failed: Request failed with status 502?**
> A 502 means the provider's servers are temporarily unavailable.
> Wait 30–60 seconds and re-run the cell, or check the provider's status page.
> See [`docs/ai_troubleshooting.md`](../docs/ai_troubleshooting.md) for more.
"""

# ╔═╡ a1b2c3d4-000a-11ea-0000-000000000001
"""
    chat(prompt; provider, model, retries, wait_s) -> String

Send `prompt` to the configured AI provider and return the response text.
Retries up to `retries` times on transient errors (e.g. 502 Bad Gateway).
"""
function chat(
	prompt::AbstractString;
	provider::String = "openai",
	model::String    = "",
	retries::Int     = 3,
	wait_s::Real     = 5,
)
	for attempt in 1:retries
		try
			return _do_chat(prompt; provider, model)
		catch e
			if attempt < retries
				@warn "AI request attempt $attempt failed: $e — retrying in $(wait_s)s"
				sleep(wait_s)
			else
				rethrow(e)
			end
		end
	end
end

# ╔═╡ a1b2c3d4-000b-11ea-0000-000000000001
function _do_chat(prompt::AbstractString; provider::String, model::String)
	if provider == "openai"
		m = isempty(model) ? "gpt-4o-mini" : model
		key = get(ENV, "OPENAI_API_KEY", "")
		isempty(key) && error("OPENAI_API_KEY is not set")
		resp = HTTP.post(
			"https://api.openai.com/v1/chat/completions",
			["Authorization" => "Bearer $key", "Content-Type" => "application/json"],
			JSON3.write(Dict(
				"model"    => m,
				"messages" => [Dict("role" => "user", "content" => prompt)],
			)),
		)
		return JSON3.read(resp.body)["choices"][1]["message"]["content"]

	elseif provider == "anthropic"
		m = isempty(model) ? "claude-3-haiku-20240307" : model
		key = get(ENV, "ANTHROPIC_API_KEY", "")
		isempty(key) && error("ANTHROPIC_API_KEY is not set")
		resp = HTTP.post(
			"https://api.anthropic.com/v1/messages",
			["x-api-key" => key, "anthropic-version" => "2023-06-01",
			 "Content-Type" => "application/json"],
			JSON3.write(Dict(
				"model"      => m,
				"max_tokens" => 1024,
				"messages"   => [Dict("role" => "user", "content" => prompt)],
			)),
		)
		return JSON3.read(resp.body)["content"][1]["text"]

	elseif provider == "ollama"
		m = isempty(model) ? "llama3" : model
		resp = HTTP.post(
			"http://localhost:11434/api/generate",
			["Content-Type" => "application/json"],
			JSON3.write(Dict("model" => m, "prompt" => prompt, "stream" => false)),
		)
		return JSON3.read(resp.body)["response"]

	else
		error("Unknown provider: $provider. Supported: openai, anthropic, ollama")
	end
end

# ╔═╡ a1b2c3d4-000c-11ea-0000-000000000001
# Uncomment and run this cell once you have set your API key:
# reply = chat("Say hello from Pluto.jl in one sentence."; provider)

# ╔═╡ a1b2c3d4-000d-11ea-0000-000000000001
md"""
## Step 5 – Verify the Response

If the cell above ran successfully, `reply` holds the model's answer.
Print it here:
"""

# ╔═╡ a1b2c3d4-000e-11ea-0000-000000000001
# reply   # ← uncomment after running Step 4

# ╔═╡ a1b2c3d4-000f-11ea-0000-000000000001
md"""
## 🎉 You're Ready!

Your AI provider is configured.  Next steps:

- Open **`sample/AI Guided Example.jl`** for a complete import → clean → analyze →
  export workflow.
- Read [`docs/ai_quickstart.md`](../docs/ai_quickstart.md) for provider options and
  privacy guidance.
- If you hit errors, consult [`docs/ai_troubleshooting.md`](../docs/ai_troubleshooting.md).
"""

# ╔═╡ Cell order:
# ╟─a1b2c3d4-0001-11ea-0000-000000000001
# ╟─a1b2c3d4-0002-11ea-0000-000000000001
# ╠═a1b2c3d4-0003-11ea-0000-000000000001
# ╟─a1b2c3d4-0004-11ea-0000-000000000001
# ╠═a1b2c3d4-0005-11ea-0000-000000000001
# ╠═a1b2c3d4-0006-11ea-0000-000000000001
# ╟─a1b2c3d4-0007-11ea-0000-000000000001
# ╠═a1b2c3d4-0008-11ea-0000-000000000001
# ╟─a1b2c3d4-0009-11ea-0000-000000000001
# ╠═a1b2c3d4-000a-11ea-0000-000000000001
# ╠═a1b2c3d4-000b-11ea-0000-000000000001
# ╠═a1b2c3d4-000c-11ea-0000-000000000001
# ╟─a1b2c3d4-000d-11ea-0000-000000000001
# ╠═a1b2c3d4-000e-11ea-0000-000000000001
# ╟─a1b2c3d4-000f-11ea-0000-000000000001
