### A Pluto.jl notebook ###
# v0.20.24

using Markdown
using InteractiveUtils

# ╔═╡ 00000000-0000-0000-0000-000000000001
# Simple arithmetic — should succeed
result = 1 + 1

# ╔═╡ 00000000-0000-0000-0000-000000000002
# Will produce a DivideError at runtime
bad_div = div(10, 0)

# ╔═╡ 00000000-0000-0000-0000-000000000003
# Will produce an UndefVarError
undefined_var + 1

# ╔═╡ 00000000-0000-0000-0000-000000000004
# Safe cell that depends only on result
doubled = result * 2

# ╔═╡ 00000000-0000-0000-0000-cell_order
# ╠═00000000-0000-0000-0000-000000000001
# ╠═00000000-0000-0000-0000-000000000002
# ╠═00000000-0000-0000-0000-000000000003
# ╠═00000000-0000-0000-0000-000000000004
