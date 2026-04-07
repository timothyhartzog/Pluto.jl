### A Pluto.jl notebook ###
# v0.20.24

using Markdown
using InteractiveUtils

# ╔═╡ b2c3d4e5-0001-11ea-0000-000000000002
md"""
# 🔬 AI-Assisted Data Analysis – Guided Example

This notebook demonstrates a complete, real-world workflow:

1. **Import** – load a CSV dataset
2. **Clean** – ask an AI to suggest and apply cleaning steps
3. **Analyse** – generate an exploratory summary with AI assistance
4. **Export** – save the cleaned data and a narrative report

> **Before you start:** make sure you have completed
> [`sample/AI Quickstart.jl`](AI%20Quickstart.jl) and that your API key is set.
>
> 📖 See [`docs/ai_quickstart.md`](../docs/ai_quickstart.md) for setup details.
"""

# ╔═╡ b2c3d4e5-0002-11ea-0000-000000000002
md"""
## Setup – Packages & Provider

Pluto installs missing packages automatically.  The first run may take a moment.
"""

# ╔═╡ b2c3d4e5-0003-11ea-0000-000000000002
begin
	import Pkg
	Pkg.add(["HTTP", "JSON3", "CSV", "DataFrames"])
end

# ╔═╡ b2c3d4e5-0004-11ea-0000-000000000002
begin
	using HTTP
	using JSON3
	using CSV
	using DataFrames
	using Statistics
	using Dates
end

# ╔═╡ b2c3d4e5-0005-11ea-0000-000000000002
# ── Provider selection ──────────────────────────────────────────────────────────
# Change to "anthropic" or "ollama" if you prefer a different provider.
ai_provider = "openai"

# ╔═╡ b2c3d4e5-0006-11ea-0000-000000000002
"""
    chat(prompt; provider, model, retries, wait_s) -> String

Send `prompt` to the configured AI provider and return the response.
Retries on transient HTTP errors such as 502 Bad Gateway.

**Tip – 502 errors:** These mean the provider is temporarily unavailable.
The function retries automatically; if errors persist, check the provider's
status page or switch to a different provider.
"""
function chat(
	prompt::AbstractString;
	provider::String = ai_provider,
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

# ╔═╡ b2c3d4e5-0007-11ea-0000-000000000002
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
				"max_tokens" => 2048,
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
		error("Unknown provider: $provider")
	end
end

# ╔═╡ b2c3d4e5-0008-11ea-0000-000000000002
md"""
---
## Step 1 – Import Data

We use a small built-in sample dataset representing monthly sales records.
In a real workflow, replace this with `CSV.read("your_file.csv", DataFrame)`.

> 🔒 **Privacy reminder:** Do not upload sensitive or personal data to a
> third-party AI provider.  If your dataset contains PII, anonymise it first
> or use a local model (provider = `"ollama"`).
"""

# ╔═╡ b2c3d4e5-0009-11ea-0000-000000000002
# Sample dataset – replace with CSV.read("your_file.csv", DataFrame) as needed
raw_df = DataFrame(
	date     = ["2024-01-15", "2024-02-20", "2024-03-05", "2024-04-10",
	            "2024-05-22", "2024-06-30", "2024-07-08", "2024-08-14",
	            "2024-09-19", "2024-10-01", "2024-11-11", "2024-12-25"],
	product  = ["Widget A", "Widget B", "Widget A", "Widget C",
	            "Widget B", "Widget A", "Widget C", "Widget A",
	            "Widget B", "Widget A", "Widget C", "Widget B"],
	quantity = [10, 25, missing, 8, 15, 30, 5, 20, 18, 12, missing, 22],
	revenue  = [150.0, 500.0, -99.0, 240.0, 300.0, 450.0, 175.0, 300.0,
	            360.0, 180.0, missing, 440.0],
	region   = ["North", "South", "North", "East", "West", "South",
	            "East", "North", "West", "South", "North", "East"],
)

# ╔═╡ b2c3d4e5-000a-11ea-0000-000000000002
md"""
**Dataset preview** ($(nrow(raw_df)) rows, $(ncol(raw_df)) columns):
"""

# ╔═╡ b2c3d4e5-000b-11ea-0000-000000000002
raw_df

# ╔═╡ b2c3d4e5-000c-11ea-0000-000000000002
md"""
---
## Step 2 – AI-Assisted Cleaning

We describe the dataset schema and ask the AI to:
1. Identify data quality issues
2. Suggest cleaning steps

Then we apply the suggestions programmatically.
"""

# ╔═╡ b2c3d4e5-000d-11ea-0000-000000000002
# Build a concise schema description to send to the AI
function describe_schema(df::DataFrame)
	lines = ["Columns and types:"]
	for col in names(df)
		n_missing = count(ismissing, df[!, col])
		push!(lines, "  - $col ($(eltype(df[!, col]))) — $n_missing missing values")
	end
	push!(lines, "Total rows: $(nrow(df))")
	join(lines, "\n")
end

schema_description = describe_schema(raw_df)

# ╔═╡ b2c3d4e5-000e-11ea-0000-000000000002
cleaning_prompt = """
You are a data quality expert. Here is the schema of a sales DataFrame:

$schema_description

Sample rows (first 3):
$(join([join(values(row), ", ") for row in eachrow(raw_df[1:3, :])], "\n"))

Identify data quality issues (missing values, invalid values, type problems) and
list specific, actionable cleaning steps in plain English. Be concise.
"""

# ╔═╡ b2c3d4e5-000f-11ea-0000-000000000002
# Uncomment to call the AI:
# cleaning_suggestions = chat(cleaning_prompt)

# Placeholder shown when no API key is available:
cleaning_suggestions = """
(AI suggestions would appear here after calling `chat(cleaning_prompt)`.)

Typical suggestions for this dataset:
1. Parse the `date` column as Date type.
2. Replace missing `quantity` values with the column median.
3. Replace the sentinel value -99 in `revenue` with `missing`, then impute.
4. Drop or impute any remaining missing `revenue` rows.
"""

# ╔═╡ b2c3d4e5-0010-11ea-0000-000000000002
md"""
**AI cleaning suggestions:**

$(cleaning_suggestions)
"""

# ╔═╡ b2c3d4e5-0011-11ea-0000-000000000002
md"""
### Apply Cleaning Steps

Based on the suggestions, we apply the following transformations:
"""

# ╔═╡ b2c3d4e5-0012-11ea-0000-000000000002
clean_df = let
	df = copy(raw_df)

	# 1. Parse date strings to Date
	df.date = Date.(df.date, "yyyy-mm-dd")

	# 2. Replace sentinel revenue value (-99) with missing
	df.revenue = replace(df.revenue, -99.0 => missing)

	# 3. Impute missing quantity with median of available values
	qty_vals = skipmissing(df.quantity)
	qty_median = median(collect(qty_vals))
	df.quantity = coalesce.(df.quantity, round(Int, qty_median))

	# 4. Impute missing revenue with column median
	rev_vals = skipmissing(df.revenue)
	rev_median = median(collect(rev_vals))
	df.revenue = coalesce.(df.revenue, rev_median)

	df
end

# ╔═╡ b2c3d4e5-0013-11ea-0000-000000000002
md"""
**Cleaned dataset** ($(count(ismissing.(Matrix(clean_df)), dims=1) |> sum) missing values remaining):
"""

# ╔═╡ b2c3d4e5-0014-11ea-0000-000000000002
clean_df

# ╔═╡ b2c3d4e5-0015-11ea-0000-000000000002
md"""
---
## Step 3 – AI-Assisted Analysis

Now we ask the AI to interpret the cleaned data and generate a narrative summary.

> ⚠️ **Always validate AI-generated insights.**  The model does not access your
> data directly — it only sees the text summary you send.  Cross-check
> statistics against your own calculations.
"""

# ╔═╡ b2c3d4e5-0016-11ea-0000-000000000002
# Compute basic statistics to include in the prompt
stats_summary = let
	by_product = combine(groupby(clean_df, :product),
		:revenue  => sum  => :total_revenue,
		:quantity => sum  => :total_quantity,
	)
	sort!(by_product, :total_revenue, rev=true)

	lines = ["Monthly sales data summary (after cleaning):"]
	push!(lines, "  Total revenue: \$$(round(sum(clean_df.revenue), digits=2))")
	push!(lines, "  Total units sold: $(sum(clean_df.quantity))")
	push!(lines, "  Date range: $(minimum(clean_df.date)) to $(maximum(clean_df.date))")
	push!(lines, "  Revenue by product:")
	for row in eachrow(by_product)
		push!(lines, "    - $(row.product): \$$(round(row.total_revenue, digits=2)) ($(row.total_quantity) units)")
	end
	push!(lines, "  Regions: $(join(unique(clean_df.region), ", "))")
	join(lines, "\n")
end

# ╔═╡ b2c3d4e5-0017-11ea-0000-000000000002
analysis_prompt = """
You are a data analyst. Based on the following summary of monthly sales data,
write a concise (3–4 paragraph) executive summary that:
1. Highlights top-performing products and regions
2. Identifies any trends or anomalies
3. Suggests one actionable next step

$stats_summary
"""

# ╔═╡ b2c3d4e5-0018-11ea-0000-000000000002
# Uncomment to call the AI:
# ai_analysis = chat(analysis_prompt)

# Placeholder:
ai_analysis = """
(AI narrative analysis would appear here after calling `chat(analysis_prompt)`.)

Example: "Widget A leads revenue across the year, concentrated in the North and
South regions. Widget B shows strong Q4 performance.  A targeted marketing
campaign in the East region, where Widget C underperforms, could improve overall
revenue by an estimated 10–15%."
"""

# ╔═╡ b2c3d4e5-0019-11ea-0000-000000000002
md"""
### 📊 Executive Summary (AI-generated)

$(ai_analysis)

---
*Note: This summary was generated by an AI model based on aggregated statistics.
Always verify conclusions against the raw data before making business decisions.*
"""

# ╔═╡ b2c3d4e5-001a-11ea-0000-000000000002
md"""
---
## Step 4 – Export Results

Export the cleaned dataset to CSV and save the AI narrative to a text file.
"""

# ╔═╡ b2c3d4e5-001b-11ea-0000-000000000002
export_dir = joinpath(homedir(), "pluto_ai_output")

# ╔═╡ b2c3d4e5-001c-11ea-0000-000000000002
# Create the output directory and write files
let
	mkpath(export_dir)

	# Cleaned CSV
	csv_path = joinpath(export_dir, "sales_cleaned.csv")
	CSV.write(csv_path, clean_df)

	# AI narrative report
	report_path = joinpath(export_dir, "ai_analysis_report.txt")
	open(report_path, "w") do io
		println(io, "AI-Assisted Sales Analysis Report")
		println(io, "Generated: $(now())")
		println(io, "="^60)
		println(io)
		println(io, stats_summary)
		println(io)
		println(io, "AI Narrative:")
		println(io, "-"^40)
		println(io, ai_analysis)
	end

	md"""
	✅ **Files written to `$export_dir`:**
	- `sales_cleaned.csv` – cleaned dataset ($(nrow(clean_df)) rows)
	- `ai_analysis_report.txt` – narrative report
	"""
end

# ╔═╡ b2c3d4e5-001d-11ea-0000-000000000002
md"""
---
## 🎓 What You Learned

| Step | What happened |
|------|--------------|
| **Import** | Loaded a raw CSV (or inline DataFrame) into Pluto |
| **Clean** | Used AI to identify issues, then applied programmatic fixes |
| **Analyse** | Sent aggregate stats to the AI for a narrative summary |
| **Export** | Saved the cleaned data and report to disk |

### Next Steps

- Replace the sample data with your own CSV file.
- Swap `ai_provider` to `"anthropic"` or `"ollama"` to try a different model.
- For larger datasets, chunk the data and call `chat` in a loop.
- If you encounter errors, see [`docs/ai_troubleshooting.md`](../docs/ai_troubleshooting.md).
"""

# ╔═╡ Cell order:
# ╟─b2c3d4e5-0001-11ea-0000-000000000002
# ╟─b2c3d4e5-0002-11ea-0000-000000000002
# ╠═b2c3d4e5-0003-11ea-0000-000000000002
# ╠═b2c3d4e5-0004-11ea-0000-000000000002
# ╠═b2c3d4e5-0005-11ea-0000-000000000002
# ╠═b2c3d4e5-0006-11ea-0000-000000000002
# ╠═b2c3d4e5-0007-11ea-0000-000000000002
# ╟─b2c3d4e5-0008-11ea-0000-000000000002
# ╠═b2c3d4e5-0009-11ea-0000-000000000002
# ╟─b2c3d4e5-000a-11ea-0000-000000000002
# ╠═b2c3d4e5-000b-11ea-0000-000000000002
# ╟─b2c3d4e5-000c-11ea-0000-000000000002
# ╠═b2c3d4e5-000d-11ea-0000-000000000002
# ╠═b2c3d4e5-000e-11ea-0000-000000000002
# ╠═b2c3d4e5-000f-11ea-0000-000000000002
# ╟─b2c3d4e5-0010-11ea-0000-000000000002
# ╟─b2c3d4e5-0011-11ea-0000-000000000002
# ╠═b2c3d4e5-0012-11ea-0000-000000000002
# ╟─b2c3d4e5-0013-11ea-0000-000000000002
# ╠═b2c3d4e5-0014-11ea-0000-000000000002
# ╟─b2c3d4e5-0015-11ea-0000-000000000002
# ╠═b2c3d4e5-0016-11ea-0000-000000000002
# ╠═b2c3d4e5-0017-11ea-0000-000000000002
# ╠═b2c3d4e5-0018-11ea-0000-000000000002
# ╟─b2c3d4e5-0019-11ea-0000-000000000002
# ╟─b2c3d4e5-001a-11ea-0000-000000000002
# ╠═b2c3d4e5-001b-11ea-0000-000000000002
# ╠═b2c3d4e5-001c-11ea-0000-000000000002
# ╟─b2c3d4e5-001d-11ea-0000-000000000002
