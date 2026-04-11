# gemtext.lua — a pandoc writer for [gemtext](https://gemini.circumlunar.space/docs/gemtext.gmi)

A single-file pandoc custom writer that outputs gemtext (the markup
language of the [Gemini protocol](https://geminiprotocol.net/)).

Because it operates on pandoc's AST it works with every input format
pandoc reads — djot, markdown, gfm, commonmark, rst, and so on. The
original motivation was djot, so the test fixtures are djot; substitute
`-f gfm` / `-f commonmark` freely.

## Requirements

- **pandoc** 2.17.2+ for the custom-writer API.
- **pandoc** 3.1.2+ if you want the native djot reader (`-f djot`).

## Usage

```sh
# Anywhere gemtext.lua lives on disk:
pandoc -f djot --to /path/to/gemtext.lua input.dj -o output.gmi

# Any other input format also works:
pandoc -f gfm README.md --to /path/to/gemtext.lua -o README.gmi
cat notes.md | pandoc -f commonmark --to /path/to/gemtext.lua
```

## Install

The Makefile copies `gemtext.lua` into pandoc's conventional custom-writer
location so you can reference it by name:

```sh
make install              # → ~/.local/share/pandoc/custom-writers/gemtext.lua
make install PREFIX=/usr/local
```

There's no binary to install — this project is the single Lua file.

## Feature mapping

gemtext is line-based and has no inline markup, so some source constructs
lose decoration. The mapping is:

| source                       | gemtext                                                  |
|------------------------------|----------------------------------------------------------|
| `# H1` … `### H3`            | `# ` / `## ` / `### ` (levels ≥ 4 capped at `###`)       |
| Paragraph                    | One text line (no hard wrapping)                         |
| `_emph_`, `*strong*`         | dropped (decorative)                                     |
| `{=mark=}`, `{+ins+}`        | dropped (decorative)                                     |
| `{-del-}`, strikeout         | wrapped `~text~` (meaning would flip if dropped)         |
| `x^2^` superscript           | leading `^` — `x^2`, `x^(n+1)` when multi-token          |
| `H~2~O` subscript            | leading `_` — `H_2O`, `f_(i,j)` when multi-token         |
| `"quoted"`                   | curly quotes `“…”` / `‘…’`                          |
| `` `code` ``                 | plain text                                               |
| inline math                  | literal TeX source                                       |
| `[text](url)`                | `[N]` in prose + `=> url N: text` after the paragraph    |
| `![alt](url)`                | same, with ` [IMG]` appended                             |
| `[^fn]` footnote             | `[^N]` marker + `## Footnotes` section at doc end        |
| `> quote`                    | `> ` prefix; any `=>` link lines moved out below         |
| Fenced code block            | ```` ``` ```` fence with language tag as alt text        |
| Bullet / ordered / task list | `* item` (gemtext has only one list type — flat bullets) |
| Thematic break               | `---`                                                    |
| Table                        | aligned plain text inside a ```` ```table ```` fence     |
| Div / span                   | walked transparently; attributes dropped                 |
| `{=format}` raw              | kept if format is `gemtext`/`gmi`, else dropped          |

**Guiding principle:** drop markers when the plain-text reading still
carries the author's meaning; preserve them when dropping would flip or
obscure it. Strikeout, delete, and super/subscript always fall in the
second bucket.

## Testing

```sh
make test
```

Fixtures live in `test/*.test` in the same plain-text format used by
[djot.js](https://github.com/jgm/djot.js) — input and expected output
separated by a `.` line inside ```` ``` ```` fences, with a description
above each block.

## Credits

- [md2gemini](https://github.com/makeworld-the-better-one/md2gemini) —
  the Python markdown→gemtext converter whose output rules this writer
  mirrors.
- [djot.js](https://github.com/jgm/djot.js) — reference djot
  implementation; the `.test` fixture format comes from it.
- [djot spec](https://github.com/jgm/djot) — the djot language.
