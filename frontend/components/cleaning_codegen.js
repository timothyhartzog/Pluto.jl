// ─── Code generators for data cleaning widgets ───────────────────────────────
// Pure functions - no UI dependencies. Exported for testing and use in CleaningWidgets.js.

// Named constants for lambda transforms to avoid duplicating string literals
/** Julia lambda that replaces one or more consecutive whitespace characters with a single space. */
export const TRANSFORM_COLLAPSE_SPACES = `x -> replace(x, r"\\s+" => " ")`
/** Julia lambda that removes all non-word, non-space characters (i.e. punctuation and symbols). */
export const TRANSFORM_REMOVE_SPECIAL = `x -> replace(x, r"[^\\w\\s]" => "")`

/**
 * Generate Julia code for duplicate handling.
 * @param {Object} opts
 * @param {string} opts.df         DataFrame variable name
 * @param {string} opts.cols       Comma-separated column names (empty = all)
 * @param {string} opts.keep       "first" | "last" | "none"
 * @param {string} opts.result     Result variable name
 */
export function gen_duplicates_code({ df, cols, keep, result }) {
    const df_name = df.trim() || "df"
    const res_name = result.trim() || "df_clean"
    const cols_list = cols
        .split(",")
        .map((c) => c.trim())
        .filter(Boolean)

    if (cols_list.length === 0) {
        // operate on all columns
        if (keep === "none") {
            return `${res_name} = begin
    dupe_mask = nonunique(${df_name})
    ${df_name}[.!dupe_mask, :]
end`
        }
        const keep_kw = keep === "last" ? "keep=:last" : "keep=:first"
        return `${res_name} = unique(${df_name}; ${keep_kw})`
    }

    // specific columns
    const cols_expr = cols_list.length === 1 ? `:${cols_list[0]}` : `[:${cols_list.join(", :")}]`
    if (keep === "none") {
        return `${res_name} = begin
    dupe_mask = nonunique(${df_name}, ${cols_expr})
    ${df_name}[.!dupe_mask, :]
end`
    }
    const keep_kw = keep === "last" ? "keep=:last" : "keep=:first"
    return `${res_name} = unique(${df_name}, ${cols_expr}; ${keep_kw})`
}

/**
 * Generate Julia code for string cleanup (clean internal helper).
 * @param {Object} opts
 * @param {string} opts.df_name
 * @param {string} opts.col_name
 * @param {string} opts.res_name
 * @param {string[]} opts.transforms  Array of Julia function expressions (e.g. "strip", "lowercase")
 */
export function gen_strings_code_clean({ df_name, col_name, res_name, transforms }) {
    if (transforms.length === 0) return `${res_name} = copy(${df_name})`

    // Build composed function string. With ∘, the rightmost is applied first,
    // so we reverse the user-ordered list so that leftmost = first applied.
    let fn_str
    if (transforms.length === 1) {
        fn_str = transforms[0]
    } else {
        fn_str = transforms.slice().reverse().join(" ∘ ")
    }
    return `${res_name} = transform(${df_name}, :${col_name} => ByRow(${fn_str}) => :${col_name})`
}

/**
 * Generate Julia code for string cleanup.
 * @param {Object} opts
 * @param {string} opts.df
 * @param {string} opts.col
 * @param {boolean} opts.do_strip
 * @param {boolean} opts.do_lowercase
 * @param {boolean} opts.do_uppercase
 * @param {boolean} opts.do_titlecase
 * @param {boolean} opts.do_collapse_spaces
 * @param {boolean} opts.do_remove_special
 * @param {string} opts.result
 */
export function gen_strings_code({ df, col, do_strip, do_lowercase, do_uppercase, do_titlecase, do_collapse_spaces, do_remove_special, result }) {
    const df_name = df.trim() || "df"
    const col_name = col.trim() || "text_col"
    const res_name = result.trim() || "df_clean"

    const transforms = []
    if (do_strip) transforms.push("strip")
    if (do_lowercase) transforms.push("lowercase")
    if (do_uppercase) transforms.push("uppercase")
    if (do_titlecase) transforms.push("titlecase")
    if (do_collapse_spaces) transforms.push(TRANSFORM_COLLAPSE_SPACES)
    if (do_remove_special) transforms.push(TRANSFORM_REMOVE_SPECIAL)

    return gen_strings_code_clean({ df_name, col_name, res_name, transforms })
}

/**
 * Generate Julia code for date parsing/standardization.
 * @param {Object} opts
 * @param {string} opts.df
 * @param {string} opts.col
 * @param {string} opts.fmt        Date format string, e.g. "yyyy-mm-dd"
 * @param {string} opts.out_fmt    "Date" | "DateTime"
 * @param {boolean} opts.coerce_missing  Replace parse failures with missing
 * @param {string} opts.result
 */
export function gen_dates_code({ df, col, fmt, out_fmt, coerce_missing, result }) {
    const df_name = df.trim() || "df"
    const col_name = col.trim() || "date_col"
    const res_name = result.trim() || "df_clean"
    const fmt_str = fmt.trim() || "yyyy-mm-dd"
    const out_type = out_fmt === "DateTime" ? "DateTime" : "Date"

    if (coerce_missing) {
        return `${res_name} = transform(${df_name},
    :${col_name} => ByRow(s -> begin
        try
            ${out_type}(string(s), dateformat"${fmt_str}")
        catch
            missing
        end
    end) => :${col_name}
)`
    }

    return `${res_name} = transform(${df_name},
    :${col_name} => ByRow(s -> ${out_type}(string(s), dateformat"${fmt_str}")) => :${col_name}
)`
}

/**
 * Returns a workflow comment block listing the cleaning steps.
 * @param {string[]} steps
 */
export function gen_workflow_comment(steps) {
    const lines = steps.map((s, i) => `# Step ${i + 1}: ${s}`).join("\n")
    return `# ── Data Cleaning Workflow ──────────────────────────────────────────\n${lines}\n# ─────────────────────────────────────────────────────────────────────`
}
