### A Pluto.jl notebook ###
# v0.19.0

using Markdown
using InteractiveUtils

# ╔═╡ a1b2c3d4-0001-11ee-0000-000000000001
# Step 1 – Import dataset (inline for deterministic tests)
raw_data = [3.0, 1.0, missing, 4.0, 1.0, 5.0, missing, 9.0, 2.0, 6.0]

# ╔═╡ a1b2c3d4-0002-11ee-0000-000000000001
# Step 2 – Profile data
profile = (
	n         = length(raw_data),
	n_missing = count(ismissing, raw_data),
	n_valid   = count(!ismissing, raw_data),
)

# ╔═╡ a1b2c3d4-0003-11ee-0000-000000000001
# Step 3 – Apply cleaning suggestion: remove missing values
cleaned = collect(skipmissing(raw_data))

# ╔═╡ a1b2c3d4-0004-11ee-0000-000000000001
# Step 4 – Analyze
result = (
	total = sum(cleaned),
	mean  = sum(cleaned) / length(cleaned),
	min   = minimum(cleaned),
	max   = maximum(cleaned),
)

# ╔═╡ Cell order:
# ╠═a1b2c3d4-0001-11ee-0000-000000000001
# ╠═a1b2c3d4-0002-11ee-0000-000000000001
# ╠═a1b2c3d4-0003-11ee-0000-000000000001
# ╠═a1b2c3d4-0004-11ee-0000-000000000001
