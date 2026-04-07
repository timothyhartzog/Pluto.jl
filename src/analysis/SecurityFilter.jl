"""
    SecurityFilter

Baseline defenses for prompt injection and unsafe code suggestions.

Provides:
- Suspicious instruction detection (`check_prompt_injection`)
- Risky code pattern detection (`check_risky_code`)
- Confirmation-gate helpers (`RiskLevel`, `SecurityWarning`)
"""
module SecurityFilter

export RiskLevel, NONE, LOW, MEDIUM, HIGH, CRITICAL
export SecurityWarning
export check_prompt_injection, check_risky_code, security_summary

# ---------------------------------------------------------------------------
# Risk levels
# ---------------------------------------------------------------------------

"""
    RiskLevel

Severity of a detected risk.

| Value | Meaning |
|-------|---------|
| `NONE` | No risk detected |
| `LOW` | Informational; no gate required |
| `MEDIUM` | Show a warning before proceeding |
| `HIGH` | Require explicit user confirmation |
| `CRITICAL` | Block by default; require strong confirmation |
"""
@enum RiskLevel NONE LOW MEDIUM HIGH CRITICAL

# ---------------------------------------------------------------------------
# SecurityWarning
# ---------------------------------------------------------------------------

"""
    SecurityWarning

Captures the outcome of a security check.

Fields:
- `risk_level::RiskLevel`
- `reasons::Vector{String}` – human-readable explanations
- `requires_confirmation::Bool` – true when risk ≥ HIGH
"""
struct SecurityWarning
    risk_level::RiskLevel
    reasons::Vector{String}
    requires_confirmation::Bool
end

SecurityWarning(level::RiskLevel, reasons::Vector{String}) =
    SecurityWarning(level, reasons, level >= HIGH)

# Convenience constructor for the no-risk case
SecurityWarning() = SecurityWarning(NONE, String[], false)

Base.show(io::IO, w::SecurityWarning) = print(
    io,
    "SecurityWarning($(w.risk_level), $(length(w.reasons)) reason(s)$(w.requires_confirmation ? ", requires_confirmation" : ""))",
)

# ---------------------------------------------------------------------------
# Prompt-injection patterns
# ---------------------------------------------------------------------------

"""
Patterns that suggest an attempt to override or bypass AI instructions.
Each entry is `(regex, risk_level, description)`.
"""
const PROMPT_INJECTION_PATTERNS = [
    # Classic jailbreak / override attempts
    (r"ignore\s+(all\s+)?(previous|prior|above|earlier)\s+(instructions?|prompts?|rules?|constraints?)"i,
     CRITICAL, "attempt to override previous instructions"),
    (r"disregard\s+(all\s+)?(previous|prior|above|earlier|your)\s+(instructions?|prompts?|rules?|constraints?)"i,
     CRITICAL, "attempt to disregard instructions"),
    (r"forget\s+(everything|all|your)\s+(you\s+know|instructions?|training|previous)"i,
     CRITICAL, "attempt to erase prior context"),
    (r"you\s+are\s+now\s+(an?\s+)?(new|different|another|uncensored|unrestricted)"i,
     HIGH, "attempt to redefine AI identity"),
    (r"act\s+as\s+(if\s+you\s+(are|were)|an?\s+)"i,
     HIGH, "persona substitution attempt"),
    (r"(pretend|imagine)\s+(you\s+are|you're|to\s+be)\s+(a\s+)?(different|unrestricted|evil|malicious)"i,
     HIGH, "role-play persona injection"),

    # System-prompt leakage / extraction
    (r"(reveal|show|print|output|repeat|tell\s+me)\s+(your\s+)?(system\s+prompt|instructions?|hidden\s+prompt)"i,
     HIGH, "attempt to extract system prompt"),
    (r"what\s+(are|were)\s+your\s+(original\s+)?(instructions?|system\s+prompt|rules?)"i,
     MEDIUM, "probe for system-level instructions"),

    # Privilege escalation / DAN / similar
    (r"\bDAN\s+(mode|jailbreak|prompt)\b",   HIGH,     "DAN jailbreak keyword"),
    (r"jailbreak",                        HIGH,     "jailbreak keyword"),
    (r"developer\s+mode",                 HIGH,     "developer-mode override attempt"),
    (r"sudo\s+mode",                      HIGH,     "sudo-mode override attempt"),
    (r"no\s+(restrictions?|limits?|filters?|safety|safeguards?)"i,
     HIGH, "attempt to remove safety restrictions"),
    (r"bypass\s+(safety|security|filter|restriction|limit)"i,
     HIGH, "explicit bypass request"),

    # Data-exfiltration instructions
    (r"(send|transmit|exfiltrate|upload|leak)\s+(all\s+)?(user\s+)?(data|credentials?|secrets?|tokens?|passwords?|keys?)"i,
     CRITICAL, "data exfiltration instruction"),
    (r"(call|fetch|request)\s+(this\s+)?(url|endpoint|webhook|server)\s+(with|using|including)\s+(user|session|auth)"i,
     HIGH, "potential credential-leaking request"),

    # Instruction injection via delimiters / injected roles
    (r"<\s*(system|human|assistant|user)\s*>",   MEDIUM, "injected role delimiter"),
    (r"\[INST\]|\[/INST\]|\[SYS\]|\[/SYS\]",    MEDIUM, "injected instruction delimiter"),
    (r"###\s*(system|instruction|human|assistant)\s*:",
     MEDIUM, "markdown-style role injection"),
]

"""
    check_prompt_injection(text::AbstractString) -> SecurityWarning

Scan `text` for prompt-injection patterns and return a `SecurityWarning`
describing the highest risk found and all matching reasons.
"""
function check_prompt_injection(text::AbstractString)::SecurityWarning
    reasons = String[]
    max_level = NONE

    for (pat, level, desc) in PROMPT_INJECTION_PATTERNS
        if occursin(pat, text)
            push!(reasons, desc)
            if level > max_level
                max_level = level
            end
        end
    end

    return SecurityWarning(max_level, reasons)
end

# ---------------------------------------------------------------------------
# Risky-code patterns
# ---------------------------------------------------------------------------

"""
Patterns for potentially dangerous Julia code.
Each entry is `(regex, risk_level, description)`.
"""
const RISKY_CODE_PATTERNS = [
    # Shell / process execution
    (r"`[^`]+`",                           HIGH,     "backtick shell execution"),
    (r"\brun\s*\(",                         HIGH,     "process execution via run()"),
    (r"\bspawn\s*\(",                       HIGH,     "process spawn"),
    (r"\bpipeline\s*\(",                    MEDIUM,   "pipeline construction (may execute commands)"),
    (r"\bBase\.Process\b",                  MEDIUM,   "direct process interface"),

    # Destructive filesystem operations
    (r"\brm\s*\(",                          HIGH,     "file/directory removal (rm)"),
    (r"\brmdir\s*\(",                       HIGH,     "directory removal (rmdir)"),
    (r"\bBase\.Filesystem\.rm\b",           HIGH,     "filesystem rm via Base"),
    (r"\bsystemcall\s*\(",                  CRITICAL, "raw system call"),

    # Dangerous file writes
    (r"\bwrite\s*\(",                       MEDIUM,   "file write"),
    (r"\bopen\s*\([^)]*,\s*[\"']w",        MEDIUM,   "file opened for writing"),
    (r"\bopen\s*\([^)]*,\s*[\"']a",        MEDIUM,   "file opened for append"),
    (r"\btruncate\s*\(",                    MEDIUM,   "file truncation"),
    (r"\bmkpath\s*\(",                      LOW,      "directory creation (mkpath)"),
    (r"\bmkdir\s*\(",                       LOW,      "directory creation (mkdir)"),

    # Dynamic code evaluation
    (r"\beval\s*\(",                        HIGH,     "dynamic code evaluation (eval)"),
    (r"\bMeta\.parse\s*\(",                 MEDIUM,   "code parsing (Meta.parse)"),
    (r"\binclude\s*\(",                     MEDIUM,   "file inclusion (include)"),
    (r"\binclude_string\s*\(",              HIGH,     "string-based include (include_string)"),
    (r"\bBase\.eval\s*\(",                  HIGH,     "Base.eval dynamic evaluation"),

    # Network / HTTP access
    (r"\bHTTP\.(get|post|put|delete|request)\s*\(",
     MEDIUM, "HTTP request"),
    (r"\bdownload\s*\(",                    MEDIUM,   "file download"),
    (r"\bSockets\.(connect|listen)\s*\(",   MEDIUM,   "raw socket connection"),
    (r"\bBase\.download\s*\(",              MEDIUM,   "Base.download"),

    # Low-level / FFI
    (r"\bccall\s*\(",                       HIGH,     "C foreign function call (ccall)"),
    (r"\b@ccall\b",                         HIGH,     "C foreign function call (@ccall)"),
    (r"\bcglobal\s*\(",                     HIGH,     "C global symbol access (cglobal)"),
    (r"\bunsafe_",                          HIGH,     "unsafe memory operation (unsafe_*)"),
    (r"\bGC\.@preserve\b",                  MEDIUM,   "GC preservation (potential unsafe access)"),

    # Environment / sensitive data access
    (r"\bENV\s*\[",                         MEDIUM,   "environment variable access"),
    (r"\bBase\.ENV\b",                      MEDIUM,   "environment access via Base.ENV"),

    # Package management
    (r"\bPkg\.(add|rm|remove|update|resolve|instantiate)\s*\(",
     HIGH, "package management operation"),
    (r"\busing\s+Pkg\b",                    LOW,      "Pkg imported"),

    # Serialization / deserialization of untrusted data
    (r"\bdeserialize\s*\(",                 HIGH,     "deserialization (unsafe with untrusted data)"),
    (r"\b(Base\.serialize|Base\.deserialize)\b",
     HIGH, "object serialization"),
]

"""
    check_risky_code(code::AbstractString) -> SecurityWarning

Scan Julia `code` for risky patterns and return a `SecurityWarning`
describing the highest risk found and all matching reasons.
"""
function check_risky_code(code::AbstractString)::SecurityWarning
    reasons = String[]
    max_level = NONE

    for (pat, level, desc) in RISKY_CODE_PATTERNS
        if occursin(pat, code)
            push!(reasons, desc)
            if level > max_level
                max_level = level
            end
        end
    end

    return SecurityWarning(max_level, reasons)
end

# ---------------------------------------------------------------------------
# Combined summary helper
# ---------------------------------------------------------------------------

"""
    security_summary(prompt::AbstractString, code::AbstractString) -> SecurityWarning

Run both `check_prompt_injection` on `prompt` and `check_risky_code` on
`code`, then return the combined worst-case `SecurityWarning`.
"""
function security_summary(prompt::AbstractString, code::AbstractString)::SecurityWarning
    inj = check_prompt_injection(prompt)
    risky = check_risky_code(code)

    max_level = max(inj.risk_level, risky.risk_level)
    reasons = vcat(inj.reasons, risky.reasons)
    return SecurityWarning(max_level, reasons)
end

end # module SecurityFilter
