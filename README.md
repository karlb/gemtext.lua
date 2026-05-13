# gemtext.lua — a pandoc writer for [gemtext](https://gemini.circumlunar.space/docs/gemtext.gmi)

A single-file pandoc custom writer that outputs gemtext (the markup
language of the [Gemini protocol](https://geminiprotocol.net/)).

Because it operates on pandoc's AST it works with every input format
pandoc reads — markdown, commonmark, gfm, rst, djot, and many more.

## Requirements

- **pandoc** 2.17.2+ for the custom-writer API.

## Install

The Makefile copies `gemtext.lua` into pandoc's conventional custom-writer
location so you can reference it by name:

```sh
make install              # → ~/.local/share/pandoc/custom/gemtext.lua
make install PREFIX=/usr/local
```

There's no binary to install — this project is the single Lua file.

## Usage

Once installed, reference the writer by name:

```sh
pandoc -f gfm README.md --to gemtext.lua -o README.gmi
cat notes.md | pandoc -f commonmark --to gemtext.lua
pandoc -f djot input.dj --to gemtext.lua -o output.gmi
```

Without installing, pass the path to the file directly:

```sh
pandoc -f gfm README.md --to /path/to/gemtext.lua -o README.gmi
```

## Feature mapping

gemtext is line-based and has no inline markup, so some source constructs
lose decoration. The mapping is:

| source construct             | gemtext                                                  |
|------------------------------|----------------------------------------------------------|
| Headings 1–3                 | `# ` / `## ` / `### ` (levels ≥ 4 capped at `###`)       |
| Paragraph                    | One text line (no hard wrapping)                         |
| Emphasis, strong             | dropped (decorative)                                     |
| Highlight, insert            | dropped (decorative)                                     |
| Strikeout, delete            | wrapped `~text~` (meaning would flip if dropped)         |
| Superscript                  | leading `^` — `x^2`, `x^(n+1)` when multi-token          |
| Subscript                    | leading `_` — `H_2O`, `f_(i,j)` when multi-token         |
| Quoted text                  | curly quotes `“…”` / `‘…’`                          |
| Inline code                  | plain text                                               |
| Inline math                  | literal TeX source                                       |
| Link                         | `[N]` in prose + `=> url N: text` after the paragraph    |
| Image                        | same, with ` [IMG]` appended                             |
| Footnote                     | `[^N]` marker + `## Footnotes` section at doc end        |
| Block quote                  | `> ` prefix; any `=>` link lines moved out below         |
| Fenced code block            | ```` ``` ```` fence with language tag as alt text        |
| Bullet / ordered / task list | `* item` (gemtext has only one list type — flat bullets) |
| Thematic break               | `---`                                                    |
| Table                        | aligned plain text inside a ```` ```table ```` fence     |
| Div / span                   | walked transparently; attributes dropped                 |
| Format-specific raw content  | kept if format is `gemtext`/`gmi`, else dropped          |

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
