-- gemtext.lua — a pandoc custom writer that outputs gemtext (the markup
-- language of the Gemini protocol).
--
-- Works with any input format pandoc reads; djot is the primary target
-- but -f gfm / -f commonmark / -f rst all produce reasonable output.
--
-- Usage:
--   pandoc -f djot --to gemtext.lua input.dj -o output.gmi
--
-- Inline links are rendered in "footnote-style per paragraph": each link
-- becomes a [N] marker in the prose, with a `=> url N: text` line emitted
-- immediately after the paragraph. Markers that would change the meaning
-- of text if dropped (strikeout/delete, super/subscript) are preserved in
-- ASCII conventions; purely decorative markers (emph, strong, mark, ins)
-- are dropped.

PANDOC_VERSION:must_be_at_least '2.17.2'

function Writer(doc, opts)
  local state = {
    footnotes = {},      -- list of { n = int, text = string }
    footnote_next = 1,
    heading_warned = false,
  }

  local function warn(msg)
    io.stderr:write("[gemtext] " .. msg .. "\n")
  end

  local function new_linkbuf()
    return { next = 1, items = {} }
  end

  -- Forward declarations so the mutual recursion works.
  local render_inline, render_inlines, render_block, render_blocks, render_table

  --------------------------------------------------------------------
  -- Inline rendering
  --------------------------------------------------------------------

  local SINGLE_TOKEN = "^[%w%.%+%-]+$"

  function render_inline(el, lb)
    local t = el.tag
    if t == "Str" then
      return el.text
    elseif t == "Space" or t == "SoftBreak" then
      return " "
    elseif t == "LineBreak" then
      return "\n"
    elseif t == "Emph" or t == "Strong" or t == "Underline" or t == "SmallCaps" then
      return render_inlines(el.content, lb)
    elseif t == "Strikeout" then
      return "~" .. render_inlines(el.content, lb) .. "~"
    elseif t == "Superscript" then
      local s = render_inlines(el.content, lb)
      if s:match(SINGLE_TOKEN) then
        return "^" .. s
      else
        return "^(" .. s .. ")"
      end
    elseif t == "Subscript" then
      local s = render_inlines(el.content, lb)
      if s:match(SINGLE_TOKEN) then
        return "_" .. s
      else
        return "_(" .. s .. ")"
      end
    elseif t == "Quoted" then
      local inner = render_inlines(el.content, lb)
      if el.quotetype == "DoubleQuote" then
        return "\u{201C}" .. inner .. "\u{201D}"
      else
        return "\u{2018}" .. inner .. "\u{2019}"
      end
    elseif t == "Code" then
      return el.text
    elseif t == "Math" then
      return el.text
    elseif t == "Span" then
      local classes = (el.attr and el.attr.classes) or {}
      for i = 1, #classes do
        local c = classes[i]
        if c == "deleted" or c == "del" or c == "strikeout" then
          return "~" .. render_inlines(el.content, lb) .. "~"
        end
      end
      return render_inlines(el.content, lb)
    elseif t == "Cite" then
      return render_inlines(el.content, lb)
    elseif t == "RawInline" then
      if el.format == "gemtext" or el.format == "gmi" then
        return el.text
      else
        return ""
      end
    elseif t == "Link" then
      local text = render_inlines(el.content, lb)
      local n = lb.next
      lb.next = n + 1
      lb.items[#lb.items + 1] = { n = n, url = el.target, text = text }
      return text .. "[" .. n .. "]"
    elseif t == "Image" then
      local text = render_inlines(el.caption or el.content or {}, lb)
      if text == "" then text = "image" end
      local n = lb.next
      lb.next = n + 1
      lb.items[#lb.items + 1] = { n = n, url = el.src, text = text .. " [IMG]" }
      return text .. "[" .. n .. "]"
    elseif t == "Note" then
      local n = state.footnote_next
      state.footnote_next = n + 1
      local sub_lb = new_linkbuf()
      local inner_parts = {}
      for i = 1, #el.content do
        local blk = el.content[i]
        if blk.tag == "Para" or blk.tag == "Plain" then
          inner_parts[#inner_parts + 1] = render_inlines(blk.content, sub_lb)
        else
          inner_parts[#inner_parts + 1] = render_block(blk)
        end
      end
      local content = table.concat(inner_parts, "\n\n")
      if #sub_lb.items > 0 then
        local link_lines = {}
        for _, item in ipairs(sub_lb.items) do
          link_lines[#link_lines + 1] = "=> " .. item.url .. " " .. item.n .. ": " .. item.text
        end
        content = content .. "\n" .. table.concat(link_lines, "\n")
      end
      state.footnotes[#state.footnotes + 1] = { n = n, text = content }
      return "[^" .. n .. "]"
    else
      return pandoc.utils.stringify(el)
    end
  end

  function render_inlines(inlines, lb)
    local parts = {}
    for i = 1, #inlines do
      parts[i] = render_inline(inlines[i], lb)
    end
    return table.concat(parts)
  end

  --------------------------------------------------------------------
  -- Block rendering
  --------------------------------------------------------------------

  local function render_para(inlines)
    local lb = new_linkbuf()
    local text = render_inlines(inlines, lb)
    if #lb.items == 0 then
      return text
    end
    local out = { text }
    for _, item in ipairs(lb.items) do
      out[#out + 1] = "=> " .. item.url .. " " .. item.n .. ": " .. item.text
    end
    return table.concat(out, "\n")
  end

  local function prefix_lines(s, prefix)
    local out = {}
    for line in (s .. "\n"):gmatch("([^\n]*)\n") do
      out[#out + 1] = prefix .. line
    end
    if out[#out] == prefix then out[#out] = nil end
    return table.concat(out, "\n")
  end

  local function render_list_items(items, marker)
    local out = {}
    for _, item_blocks in ipairs(items) do
      local rendered = render_blocks(item_blocks):gsub("\n+$", "")
      local lines = {}
      local first = true
      for line in (rendered .. "\n"):gmatch("([^\n]*)\n") do
        if first then
          lines[#lines + 1] = marker .. line
          first = false
        else
          lines[#lines + 1] = "  " .. line
        end
      end
      out[#out + 1] = table.concat(lines, "\n")
    end
    return table.concat(out, "\n")
  end

  function render_block(b)
    local t = b.tag
    if t == "Para" or t == "Plain" then
      return render_para(b.content)
    elseif t == "Header" then
      local level = b.level
      if level > 3 then
        if not state.heading_warned then
          warn("heading level " .. level .. " capped at 3 (gemtext has only #/##/###)")
          state.heading_warned = true
        end
        level = 3
      end
      local lb = new_linkbuf()
      local text = render_inlines(b.content, lb)
      return string.rep("#", level) .. " " .. text
    elseif t == "BlockQuote" then
      local inner = render_blocks(b.content)
      local prefixed = prefix_lines(inner, "> ")
      -- Gemini clients only recognize `=> ` at start-of-line, so a
      -- `> => ...` line is rendered as quoted text, not a link. Pull any
      -- such lines out of the quote block and emit them unprefixed
      -- beneath it so the links remain clickable.
      local quote_lines, link_lines = {}, {}
      for line in (prefixed .. "\n"):gmatch("([^\n]*)\n") do
        local link = line:match("^> (=> .*)$")
        if link then
          link_lines[#link_lines + 1] = link
        else
          quote_lines[#quote_lines + 1] = line
        end
      end
      while #quote_lines > 0 and quote_lines[#quote_lines] == "" do
        quote_lines[#quote_lines] = nil
      end
      local result = table.concat(quote_lines, "\n")
      if #link_lines > 0 then
        if result ~= "" then result = result .. "\n" end
        result = result .. table.concat(link_lines, "\n")
      end
      return result
    elseif t == "CodeBlock" then
      local classes = (b.attr and b.attr.classes) or {}
      local lang = classes[1]
      local header = lang and ("```" .. lang) or "```"
      local body = b.text
      if body:sub(-1) == "\n" then body = body:sub(1, -2) end
      return header .. "\n" .. body .. "\n```"
    elseif t == "BulletList" then
      return render_list_items(b.content, "* ")
    elseif t == "OrderedList" then
      return render_list_items(b.content, "* ")
    elseif t == "DefinitionList" then
      local out = {}
      for _, pair in ipairs(b.content) do
        local term_inlines, defs = pair[1], pair[2]
        local lb = new_linkbuf()
        local term = render_inlines(term_inlines, lb)
        for _, def_blocks in ipairs(defs) do
          local def_text = render_blocks(def_blocks):gsub("\n+$", "")
          out[#out + 1] = "* " .. term .. ": " .. def_text
        end
      end
      return table.concat(out, "\n")
    elseif t == "HorizontalRule" then
      return "---"
    elseif t == "Table" then
      return render_table(b)
    elseif t == "Div" then
      return render_blocks(b.content)
    elseif t == "LineBlock" then
      local out = {}
      for _, inlines in ipairs(b.content) do
        local lb = new_linkbuf()
        out[#out + 1] = render_inlines(inlines, lb)
        for _, item in ipairs(lb.items) do
          out[#out + 1] = "=> " .. item.url .. " " .. item.n .. ": " .. item.text
        end
      end
      return table.concat(out, "\n")
    elseif t == "RawBlock" then
      if b.format == "gemtext" or b.format == "gmi" then
        return b.text
      end
      warn("dropped raw block of format " .. tostring(b.format))
      return ""
    elseif t == "Figure" then
      return render_blocks(b.content)
    else
      warn("unhandled block type: " .. tostring(t))
      return ""
    end
  end

  function render_blocks(blocks)
    local out = {}
    for i = 1, #blocks do
      local r = render_block(blocks[i])
      if r and r ~= "" then
        out[#out + 1] = r
      end
    end
    return table.concat(out, "\n\n")
  end

  --------------------------------------------------------------------
  -- Tables: render as aligned plain text inside a ```table fence.
  --------------------------------------------------------------------

  local function cells_of_row(row)
    local cells = {}
    for _, cell in ipairs(row.cells) do
      local rendered = render_blocks(cell.contents)
        :gsub("\n", " ")
        :gsub("%s+", " ")
        :gsub("^%s+", "")
        :gsub("%s+$", "")
      cells[#cells + 1] = rendered
    end
    return cells
  end

  function render_table(tbl)
    local head_rows = {}
    for _, row in ipairs(tbl.head.rows or {}) do
      head_rows[#head_rows + 1] = cells_of_row(row)
    end
    local body_rows = {}
    for _, tb in ipairs(tbl.bodies or {}) do
      for _, row in ipairs(tb.body or {}) do
        body_rows[#body_rows + 1] = cells_of_row(row)
      end
    end

    local all_rows = {}
    for _, r in ipairs(head_rows) do all_rows[#all_rows + 1] = r end
    for _, r in ipairs(body_rows) do all_rows[#all_rows + 1] = r end
    if #all_rows == 0 then return "" end

    local ncols = 0
    for _, r in ipairs(all_rows) do
      if #r > ncols then ncols = #r end
    end
    local widths = {}
    for c = 1, ncols do
      widths[c] = 0
      for _, r in ipairs(all_rows) do
        local w = #(r[c] or "")
        if w > widths[c] then widths[c] = w end
      end
    end

    local function fmt_row(r)
      local parts = {}
      for c = 1, ncols do
        local cell = r[c] or ""
        parts[c] = cell .. string.rep(" ", widths[c] - #cell)
      end
      return "| " .. table.concat(parts, " | ") .. " |"
    end

    local sep_parts = {}
    for c = 1, ncols do sep_parts[c] = string.rep("-", widths[c]) end
    local sep = "|-" .. table.concat(sep_parts, "-|-") .. "-|"

    local lines = { "```table" }
    for _, r in ipairs(head_rows) do lines[#lines + 1] = fmt_row(r) end
    if #head_rows > 0 then lines[#lines + 1] = sep end
    for _, r in ipairs(body_rows) do lines[#lines + 1] = fmt_row(r) end
    lines[#lines + 1] = "```"
    return table.concat(lines, "\n")
  end

  --------------------------------------------------------------------
  -- Entry point
  --------------------------------------------------------------------

  local out = render_blocks(doc.blocks)

  if #state.footnotes > 0 then
    local fn_lines = { "", "## Footnotes", "" }
    for _, fn in ipairs(state.footnotes) do
      local indented = fn.text:gsub("\n", "\n   ")
      fn_lines[#fn_lines + 1] = fn.n .. ". " .. indented
    end
    out = out .. "\n\n" .. table.concat(fn_lines, "\n"):gsub("^\n", "")
  end

  if out:sub(-1) ~= "\n" then out = out .. "\n" end
  return out
end
