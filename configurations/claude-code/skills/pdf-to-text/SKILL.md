---
name: pdf-to-text
description: "Convert PDFs to text for downstream processing, verify extraction accuracy by rendering pages to images and comparing, and fix common pdftotext artifacts (orphan page-break labels, repeated page-top breadcrumbs interposed in content, word splits across column/page boundaries, inlined callout annotations in code blocks). Use when the user asks to convert, extract, or OCR PDFs, or to verify text extracted from a PDF."
---

# PDF to text

Convert PDFs to text that is accurate enough for downstream parsing or LLM processing. The `pdftotext` defaults handle simple cases, but wiki exports, multi-column layouts, and paginated tables introduce extraction artifacts that need targeted cleanup. This skill pairs text extraction with image-based verification so you can tell the difference between a source typo (preserve) and an extraction bug (fix).

## Tools

All commands come from `poppler-utils`. On NixOS:

```bash
nix shell nixpkgs#poppler-utils -c <command>
```

- `pdfinfo FILE.pdf` — page count and metadata.
- `pdftotext -layout FILE.pdf OUT.txt` — extract text preserving column structure. Always use `-layout`; the default reflow mode loses column ordering and destroys tables.
- `pdftoppm -r 150 -png FILE.pdf PREFIX` — render each page to `PREFIX-1.png`, `PREFIX-2.png`, … at 150 dpi. High enough for a multimodal reader to see small type without bloating tokens.

## Procedure

### 1. Extract and render

Batch both operations in a single nix shell to avoid startup cost:

```bash
mkdir -p text images
nix shell nixpkgs#poppler-utils -c bash -c '
  for f in *.pdf; do
    pdftotext -layout "$f" "text/${f%.pdf}.txt"
    pdftoppm -r 150 -png "$f" "images/${f%.pdf}"
  done
'
```

For mixed batches where filenames are long or overlapping, rename image prefixes with a numeric index (`01`, `02`, …) so a document's pages stay grouped: `images/01-1.png`, `images/01-2.png`, etc.

### 2. Verify against rendered images

Read each page PNG and the extracted text in parallel — one tool call per file. The multimodal Read tool consumes PNGs directly; no OCR layer needed.

Check:

- **Completeness** — every visible text block in the image appears in the text.
- **Ordering** — reading order is preserved across columns and page breaks.
- **Fidelity** — wording matches exactly, including source typos. Do not "correct" typos that exist in the source PDF.

Embedded diagrams, screenshots, and chart images are not text-extractable and will not appear in the output. Note which diagrams are missing so the user knows what is unrecovered. If diagram content is actually needed, that requires OCR or a vision model reading the rendered page PNGs — outside the scope of this procedure.

### 3. Classify each difference

- **Source artifact** (typo, broken grammar, awkward phrasing present in the PDF itself): preserve verbatim. The extraction is doing its job.
- **Extraction artifact** (introduced by `pdftotext`): fix.

When in doubt, look at the exact bytes in the text file (`awk 'NR==N' file.txt`) and compare to the image at that position.

### 4. Fix extraction artifacts

Use targeted `Edit` or `perl -i`. Do not re-run `pdftotext` with different flags as a blanket fix — you will lose `-layout` column preservation and regress pages that were correct.

## Common artifacts and fixes

### Orphan list labels at page breaks

A list item's letter or number appears alone at a page boundary, with the actual content repeated at the top of the next page:

```
               the previous paragraph ended here.

            d.
        d. The actual content of item d starts here…
```

Fix: remove the orphan line. The real content starts on the next identically-labeled line.

### Repeated page-top breadcrumbs interposed in content

Wiki and documentation tools often print a navigation breadcrumb (e.g. `Pages / … / Section Name`) at the top of every page. `pdftotext -layout` places each copy at its spatial y-coordinate on the page, which can land mid-content — most disruptively splitting a comment author from their timestamp:

```
               Author Name
         / … / Section Name
               Mon DD, YYYY
```

Fix: keep the first occurrence (the legitimate document breadcrumb) and drop duplicates.

```bash
perl -i -ne 'BEGIN{$c=0}
  if (/^\s+\/ … \/ SECTION NAME\s*$/) { $c++; print if $c == 1 }
  else { print }
' FILE.txt
```

Substitute the exact breadcrumb text from the document.

### Word split across a page or narrow column

A single word gets broken across two lines when it straddled a page break or a narrow table column:

```
…some content ending in tha
                                            n Some content beginning here
```

Fix: join the fragments. In a multi-column table, target both lines precisely so you do not disturb neighboring columns.

```bash
perl -i -pe '
  s{tha$}{than};
  s{    n Some content}{    Some content};
' FILE.txt
```

### Inlined callout annotations in code blocks

Some wiki tools render floating annotations beside specific lines of a code block. `pdftotext` collapses those callouts onto the same line as the code, corrupting the block for any parser:

```
"field": "value", Annotation explaining this field
```

Fix: add a comment marker (`//`) so the annotation is syntactically separated from the data. For JSON this produces JSON5/JSONC — document it in the handoff so downstream consumers that need strict JSON know to strip comments.

```bash
perl -i -pe 's{"field": "value", Annotation}{"field": "value", // Annotation};' FILE.txt
```

## Tips

- Batch extraction and rendering for a whole directory inside one `nix shell` invocation. The shell startup dominates per-file cost.
- When verifying many PDFs, fire image reads and text reads for one document in parallel, move to the next document only after you have classified findings for the current one.
- Preserve source typos. Silent "corrections" diverge the text from the original and break auditability.
- `pdftotext` without `-layout` is not a shortcut around column artifacts — it produces worse artifacts and loses table structure entirely. Stay on `-layout` and fix the artifacts post-hoc.
- Inspect exact bytes with `awk 'NR>=N && NR<=M {printf "%d: [%s]\n", NR, $0}' file.txt` before crafting an `Edit` — leading whitespace from `-layout` is often what makes string matches fail.
