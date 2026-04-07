import { gen_duplicates_code, gen_strings_code_clean, gen_dates_code } from "../../../frontend/components/cleaning_codegen.js"

// ─── gen_duplicates_code ──────────────────────────────────────────────────────

describe("gen_duplicates_code", () => {
    it("all columns, keep first (default)", () => {
        const code = gen_duplicates_code({ df: "df", cols: "", keep: "first", result: "out" })
        expect(code).toContain("unique(df")
        expect(code).toContain("keep=:first")
        expect(code).toMatch(/^out\s*=/)
    })

    it("all columns, keep last", () => {
        const code = gen_duplicates_code({ df: "df", cols: "", keep: "last", result: "out" })
        expect(code).toContain("keep=:last")
    })

    it("all columns, keep none (remove all duplicates)", () => {
        const code = gen_duplicates_code({ df: "df", cols: "", keep: "none", result: "out" })
        expect(code).toContain("nonunique")
        expect(code).not.toContain("keep=:")
    })

    it("specific columns, keep first", () => {
        const code = gen_duplicates_code({ df: "mydf", cols: "col1, col2", keep: "first", result: "res" })
        expect(code).toContain(":col1")
        expect(code).toContain(":col2")
        expect(code).toContain("keep=:first")
        expect(code).toMatch(/^res\s*=/)
    })

    it("specific columns, keep none", () => {
        const code = gen_duplicates_code({ df: "mydf", cols: "id", keep: "none", result: "res" })
        expect(code).toContain("nonunique")
        expect(code).toContain(":id")
    })

    it("uses defaults when df/result are empty", () => {
        const code = gen_duplicates_code({ df: "", cols: "", keep: "first", result: "" })
        expect(code).toContain("df")
        expect(code).toContain("df_clean")
    })
})

// ─── gen_strings_code_clean ───────────────────────────────────────────────────

describe("gen_strings_code_clean", () => {
    it("single transform (strip)", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "name", res_name: "out", transforms: ["strip"] })
        expect(code).toContain("ByRow(strip)")
        expect(code).toContain(":name")
        expect(code).toMatch(/^out\s*=/)
    })

    it("lowercase transform", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "text", res_name: "clean", transforms: ["lowercase"] })
        expect(code).toContain("ByRow(lowercase)")
    })

    it("uppercase transform", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "text", res_name: "clean", transforms: ["uppercase"] })
        expect(code).toContain("ByRow(uppercase)")
    })

    it("titlecase transform", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "text", res_name: "clean", transforms: ["titlecase"] })
        expect(code).toContain("ByRow(titlecase)")
    })

    it("multiple transforms are composed with ∘", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "text", res_name: "out", transforms: ["strip", "lowercase"] })
        expect(code).toContain("∘")
        expect(code).toContain("strip")
        expect(code).toContain("lowercase")
    })

    it("no transforms gives copy statement", () => {
        const code = gen_strings_code_clean({ df_name: "df", col_name: "text", res_name: "out", transforms: [] })
        expect(code).toContain("copy(df)")
    })

    it("uses transform(df, ...) pattern", () => {
        const code = gen_strings_code_clean({ df_name: "mydf", col_name: "col", res_name: "result", transforms: ["strip"] })
        expect(code).toContain("transform(mydf")
    })
})

// ─── gen_dates_code ───────────────────────────────────────────────────────────

describe("gen_dates_code", () => {
    it("basic Date parsing without coerce", () => {
        const code = gen_dates_code({ df: "df", col: "date_col", fmt: "yyyy-mm-dd", out_fmt: "Date", coerce_missing: false, result: "out" })
        expect(code).toContain("Date(")
        expect(code).toContain('dateformat"yyyy-mm-dd"')
        expect(code).toContain(":date_col")
        expect(code).toMatch(/^out\s*=/)
        expect(code).not.toContain("try")
    })

    it("DateTime parsing", () => {
        const code = gen_dates_code({ df: "df", col: "ts", fmt: "yyyy-mm-dd HH:MM:SS", out_fmt: "DateTime", coerce_missing: false, result: "out" })
        expect(code).toContain("DateTime(")
        expect(code).toContain('dateformat"yyyy-mm-dd HH:MM:SS"')
    })

    it("coerce_missing wraps in try/catch", () => {
        const code = gen_dates_code({ df: "df", col: "date_col", fmt: "dd/mm/yyyy", out_fmt: "Date", coerce_missing: true, result: "out" })
        expect(code).toContain("try")
        expect(code).toContain("missing")
        expect(code).toContain('dateformat"dd/mm/yyyy"')
    })

    it("uses defaults when df/result are empty", () => {
        const code = gen_dates_code({ df: "", col: "", fmt: "", out_fmt: "Date", coerce_missing: false, result: "" })
        expect(code).toContain("df")
        expect(code).toContain("df_clean")
        expect(code).toContain("date_col")
        expect(code).toContain("yyyy-mm-dd")
    })

    it("result variable name appears at start", () => {
        const code = gen_dates_code({ df: "mydf", col: "col", fmt: "mm/dd/yyyy", out_fmt: "Date", coerce_missing: false, result: "parsed_df" })
        expect(code).toMatch(/^parsed_df\s*=/)
    })
})
