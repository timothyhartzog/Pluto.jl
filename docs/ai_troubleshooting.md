# AI Features – Troubleshooting & Known Limitations

## Common Errors

### `Assignment failed: Request failed with status 502`

**What it means:**  
A 502 (Bad Gateway) response indicates that the upstream AI provider's servers
returned an invalid response to the gateway that Pluto (or your HTTP client)
connected to.  In practice this almost always means the provider is temporarily
unavailable, overloaded, or undergoing maintenance — it is rarely a problem
with your code or credentials.

**What to try:**

1. **Wait and retry.** 502 errors are usually transient. Wait 30–60 seconds and
   re-run the cell.

2. **Check the provider status page.**
   - OpenAI: <https://status.openai.com/>
   - Anthropic: <https://status.anthropic.com/>
   - Mistral: <https://mistral.ai/status>

3. **Add a retry loop in your notebook:**

   ```julia
   import HTTP, JSON3

   function chat_with_retry(prompt; retries=3, wait_s=5)
       for attempt in 1:retries
           try
               resp = HTTP.post(
                   "https://api.openai.com/v1/chat/completions",
                   ["Authorization" => "Bearer $(ENV["OPENAI_API_KEY"])",
                    "Content-Type"  => "application/json"],
                   JSON3.write(Dict(
                       "model"    => "gpt-4o-mini",
                       "messages" => [Dict("role" => "user", "content" => prompt)],
                   ))
               )
               return JSON3.read(resp.body)["choices"][1]["message"]["content"]
           catch e
               if attempt < retries
                   @warn "Attempt $attempt failed: $e  — retrying in $(wait_s)s"
                   sleep(wait_s)
               else
                   rethrow(e)
               end
           end
       end
   end
   ```

4. **Switch to a different provider or model** as a temporary workaround.

---

### `401 Unauthorized`

Your API key is missing, incorrect, or expired.

- Verify `ENV["OPENAI_API_KEY"]` (or the relevant variable) is set in the
  Julia process that Pluto started.  Run `ENV["OPENAI_API_KEY"]` in a cell —
  the output should **not** be `missing` or empty.
- Make sure you set the key **before** starting Pluto (see the
  [Quickstart guide](ai_quickstart.md)).
- Regenerate the key on the provider's dashboard if necessary.

---

### `429 Too Many Requests`

You have exceeded your rate limit or quota.

- Wait for the retry period shown in the response header (`Retry-After`).
- Reduce the frequency of requests in your notebook (add `sleep(1)` between
  calls, or cache results).
- Upgrade your API plan if you hit hard quotas.

---

### `504 Gateway Timeout`

The provider took too long to respond.  This can happen with very long prompts
or at peak usage times.

- Reduce the amount of data in your prompt.
- Retry during off-peak hours.
- Use streaming responses if the provider supports them.

---

### Package not found / `LoadError`

If you see errors like `Package HTTP not found`, Pluto's built-in package
manager needs to install the dependency.  Simply wait for the status bar to
finish installing, then re-run the cell.  If it gets stuck:

1. Click the package manager icon (📦) in the lower-right corner.
2. Check for unresolved conflicts.
3. As a last resort, open the notebook in a fresh Pluto session.

---

### Responses that look correct but contain wrong data ("hallucinations")

AI models do not look up real data — they generate plausible-sounding text
based on patterns in their training data.  Always:

- Cross-check numerical results against your original dataset.
- Use the AI for code generation and summaries, not as a ground-truth source.
- Store the AI response in a variable and inspect it before using it downstream.

---

## Known Limitations

| Limitation | Details |
|------------|---------|
| **Non-determinism** | The same prompt can return different responses each run. Set `temperature=0` for more consistent outputs, or cache responses. |
| **Context window limits** | Large DataFrames cannot be sent in a single prompt. Summarise or chunk your data before sending. |
| **Rate limits** | Free-tier plans have low request-per-minute limits. Batch your analysis or upgrade your plan. |
| **Latency** | API round-trips add seconds of wait time. Long analyses may feel sluggish compared to local computation. |
| **Cost** | Each token sent and received is billed. Monitor usage on your provider dashboard to avoid surprises. |
| **Privacy** | Data sent to third-party APIs leaves your machine. Use a local model (e.g., Ollama) for sensitive data. |
| **No real-time data** | LLMs have a knowledge cut-off date. For current data, provide it explicitly in the prompt. |

---

## Getting More Help

- Open a discussion on the [Pluto GitHub repository](https://github.com/JuliaPluto/Pluto.jl/discussions).
- Check the [FAQ wiki](https://github.com/JuliaPluto/Pluto.jl/wiki).
- Use the built-in **Instant feedback** form in the bottom-right of any Pluto window.
