local TextProcessor = {}

local function split_lines_with_offsets(text)
  local lines = {}
  local start = 1
  local row = 0

  while start <= #text do
    local nl = text:find("\n", start, true)
    if nl then
      table.insert(lines, {
        row = row,
        text = text:sub(start, nl - 1),
        abs_start = start,
        abs_end = nl - 1,
      })
      start = nl + 1
      row = row + 1
    else
      table.insert(lines, {
        row = row,
        text = text:sub(start),
        abs_start = start,
        abs_end = #text,
      })
      break
    end
  end

  if #lines == 0 then
    table.insert(lines, { row = 0, text = "", abs_start = 1, abs_end = 0 })
  end

  return lines
end

local function abs_to_row_col(lines, abs_pos)
  for _, line in ipairs(lines) do
    if abs_pos >= line.abs_start and abs_pos <= math.max(line.abs_end, line.abs_start) then
      return line.row, abs_pos - line.abs_start
    end
  end

  local last = lines[#lines]
  return last.row, math.max(0, abs_pos - last.abs_start)
end

function TextProcessor.findControlPatternRangesInText(text, callback)
  local lines = split_lines_with_offsets(text)
  local i = 1
  local quoteIndex = 0
  local state = {
    currIdent = nil,
    currIdentStart = nil,
    currIdentEnd = nil,
    lastIdentifier = nil,
  }

  local function char_at(pos)
    return text:sub(pos, pos)
  end

  while i <= #text do
    local char = char_at(i)

    if char == '"' then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = i + 1
      while j <= #text and char_at(j) ~= '"' do
        j = j + 1
      end

      if j <= #text then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "quote",
          start_pos = i,
          inner_start = i + 1,
          inner_end = j - 1,
          end_pos = j,
          content = text:sub(i + 1, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
          lines = lines,
        })
        i = j + 1
      else
        i = i + 1
      end
    elseif text:sub(i, i + 2) == "[m|" then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = text:find("|]", i + 3, true)
      if j then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "mondo",
          start_pos = i,
          inner_start = i + 3,
          inner_end = j - 1,
          end_pos = j + 1,
          content = text:sub(i + 3, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
          lines = lines,
        })
        i = j + 2
      else
        i = i + 1
      end
    elseif text:sub(i, i + 6) == "[mondo|" then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = text:find("|]", i + 7, true)
      if j then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "mondo",
          start_pos = i,
          inner_start = i + 7,
          inner_end = j - 1,
          end_pos = j + 1,
          content = text:sub(i + 7, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
          lines = lines,
        })
        i = j + 2
      else
        i = i + 1
      end
    else
      local c = char
      if state.currIdent == nil then
        if c:match("[%a_]") then
          state.currIdent = c
          state.currIdentStart = i
          state.currIdentEnd = i
        end
      else
        if c:match("[%w_']") then
          state.currIdent = state.currIdent .. c
          state.currIdentEnd = i
        else
          state.lastIdentifier = state.currIdent
          state.currIdent = nil
          state.currIdentStart = nil
          state.currIdentEnd = nil
        end
      end
      i = i + 1
    end
  end
end

local DIGIT_MIN = 48
local DIGIT_MAX = 57
local UPPERCASE_MIN = 65
local UPPERCASE_MAX = 90
local LOWERCASE_MIN = 97
local LOWERCASE_MAX = 122
local DOT = 46
local MINUS = 45
local COLON = 58
local QUOTATION_MARK = 34

local function charCodeAt(str, idx)
  return string.byte(str, idx, idx)
end

function TextProcessor.isValidTidalWordChar(character)
  local code = charCodeAt(character, 1)
  return (code >= DIGIT_MIN and code <= DIGIT_MAX)
      or (code >= UPPERCASE_MIN and code <= UPPERCASE_MAX)
      or (code >= LOWERCASE_MIN and code <= LOWERCASE_MAX)
      or (code == DOT)
      or (code == MINUS)
      or (code == COLON)
end

function TextProcessor.isQuotationMark(character)
  return charCodeAt(character, 1) == QUOTATION_MARK
end

local function isIdentStart(char)
  return char and char:match("[%a_]")
end

local function isIdentChar(char)
  return char and char:match("[%w_']")
end

local function scanOutsideIdentifiers(line, i, state)
  local char = line:sub(i, i)

  if state.currIdent == nil then
    if isIdentStart(char) then
      state.currIdent = char
      state.currIdentStart = i
      state.currIdentEnd = i
    end
  else
    if isIdentChar(char) then
      state.currIdent = state.currIdent .. char
      state.currIdentEnd = i
    else
      state.lastIdentifier = state.currIdent
      state.currIdent = nil
      state.currIdentStart = nil
      state.currIdentEnd = nil
    end
  end
end

function TextProcessor.findControlPatternRanges(line, callback)
  local i = 1
  local quoteIndex = 0

  local state = {
    currIdent = nil,
    currIdentStart = nil,
    currIdentEnd = nil,
    lastIdentifier = nil,
  }

  while i <= #line do
    local char = line:sub(i, i)

    if char == '"' then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = i + 1
      while j <= #line and line:sub(j, j) ~= '"' do
        j = j + 1
      end

      if j <= #line then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "quote",
          start_pos = i,
          inner_start = i + 1,
          inner_end = j - 1,
          end_pos = j,
          content = line:sub(i + 1, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
        })
        i = j + 1
      else
        i = i + 1
      end
    elseif line:sub(i, i + 2) == "[m|" then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = line:find("|]", i + 3, true)
      if j then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "mondo",
          start_pos = i,
          inner_start = i + 3,
          inner_end = j - 1,
          end_pos = j + 1,
          content = line:sub(i + 3, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
        })
        i = j + 2
      else
        i = i + 1
      end
    elseif line:sub(i, i + 6) == "[mondo|" then
      if state.currIdent then
        state.lastIdentifier = state.currIdent
        state.currIdent = nil
        state.currIdentStart = nil
        state.currIdentEnd = nil
      end

      local j = line:find("|]", i + 7, true)
      if j then
        quoteIndex = quoteIndex + 1
        callback({
          kind = "mondo",
          start_pos = i,
          inner_start = i + 7,
          inner_end = j - 1,
          end_pos = j + 1,
          content = line:sub(i + 7, j - 1),
          function_name = state.lastIdentifier or "",
          quote_index = quoteIndex,
        })
        i = j + 2
      else
        i = i + 1
      end
    else
      scanOutsideIdentifiers(line, i, state)
      i = i + 1
    end
  end
end

local function emitQuotedRanges(block, callback)
  local startPos, endPos = nil, nil

  for i = block.inner_start, block.inner_end do
    local char = block.content:sub(i - block.inner_start + 1, i - block.inner_start + 1)

    if TextProcessor.isValidTidalWordChar(char) then
      if startPos == nil then
        startPos = i
      end
      endPos = i
    else
      if startPos ~= nil and endPos ~= nil then
        callback({
          range_start = startPos,
          range_end = endPos,
          function_name = block.function_name or "",
          quote_index = block.quote_index,
        })
      end
      startPos, endPos = nil, nil
    end
  end

  if startPos ~= nil and endPos ~= nil then
    callback({
      range_start = startPos,
      range_end = endPos,
      function_name = block.function_name or "",
      quote_index = block.quote_index,
    })
  end
end

local function emitMondoRanges(block, callback)
  local i = block.inner_start
  local currentControl = nil
  local expectingControl = true
  local text = block.content
  local base = block.inner_start - 1

  local function char_at_abs(abs_pos)
    return text:sub(abs_pos - base, abs_pos - base)
  end

  while i <= block.inner_end do
    local char = char_at_abs(i)

    if char == "#" then
      currentControl = nil
      expectingControl = true
      i = i + 1
    elseif TextProcessor.isValidTidalWordChar(char) then
      local tokenStart = i
      local tokenEnd = i

      while tokenEnd + 1 <= block.inner_end do
        local nextChar = char_at_abs(tokenEnd + 1)
        if TextProcessor.isValidTidalWordChar(nextChar) then
          tokenEnd = tokenEnd + 1
        else
          break
        end
      end

      local token = text:sub(tokenStart - base, tokenEnd - base)

      if expectingControl then
        currentControl = token
        expectingControl = false
      else
        local rowStart, colStart = abs_to_row_col(block.lines, tokenStart)
        local _, colEnd = abs_to_row_col(block.lines, tokenEnd)

        callback({
          row = rowStart,
          range_start = colStart,
          range_end = colEnd,
          function_name = currentControl or block.function_name or "",
          originalText = token,
          quote_index = block.quote_index,
        })
      end

      i = tokenEnd + 1
    else
      i = i + 1
    end
  end
end

function TextProcessor.findTidalWordRanges(text, callback)
  TextProcessor.findControlPatternRangesInText(text, function(block)
    if block.kind == "quote" then
      -- pode adaptar depois se quiser row/col em strings também
    elseif block.kind == "mondo" then
      emitMondoRanges(block, callback)
    end
  end)
end

function TextProcessor.controlPatternsRegex()
  return '()"([^"]-)"()'
end

function TextProcessor.exceptedFunctionPatterns()
  return [[numerals%s*=.*$|p%s.*$]]
end

return TextProcessor
