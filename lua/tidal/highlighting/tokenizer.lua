local Tokenizer = {}

local lineProcessor = require("tidal.highlighting.lineprocessor")
local marker = require("tidal.highlighting.marker")

Tokenizer.lastEventId = 0

local function splice_replacements(line, replacements)
  table.sort(replacements, function(a, b)
    return a.start_pos > b.start_pos
  end)

  local out = line
  for _, repl in ipairs(replacements) do
    out = out:sub(1, repl.start_pos - 1) .. repl.replacement .. out:sub(repl.end_pos + 1)
  end
  return out
end

function Tokenizer.addDeltaContext(text, eventId)
  if text:match("^:") then
    return text
  end

  local replacements = {}

  lineProcessor.findControlPatternRangesInText(text, function(block)
    local before = text:sub(1, block.start_pos - 1)

    if before:match(lineProcessor.exceptedFunctionPatterns()) then
      return
    end

    if block.kind == "quote" then
      table.insert(replacements, {
        start_pos = block.start_pos,
        end_pos = block.end_pos,
        replacement = string.format('(deltaContext %i %i "%s")', block.start_pos - 1, eventId, block.content),
      })
    elseif block.kind == "mondo" then
      local expr = text:sub(block.start_pos, block.end_pos)
      table.insert(replacements, {
        start_pos = block.start_pos,
        end_pos = block.end_pos,
        replacement = string.format("(deltaContext %i %i %s)", block.start_pos - 1, eventId, expr),
      })
    end
  end)

  if #replacements == 0 then
    return text
  end

  return splice_replacements(text, replacements)
end

local function findReplacementRanges(line)
  local replacements = {}
  lineProcessor.findTidalWordRanges(line, function(replacement)
    table.insert(replacements, replacement)
  end)
  return replacements
end

local function updateEventId()
  Tokenizer.lastEventId = Tokenizer.lastEventId + 1
end

function Tokenizer.addMetadata(text, startRow)
  local replacements = {}
  lineProcessor.findTidalWordRanges(text, function(replacement)
    if replacement.row ~= nil then
      replacement.row = (startRow or 1) + replacement.row - 1 -- resultado 0-based
    end
    table.insert(replacements, replacement)
  end)

  if #replacements > 0 then
    updateEventId()
    marker.createMarkers(replacements, startRow, Tokenizer.lastEventId)
    return Tokenizer.addDeltaContext(text, Tokenizer.lastEventId)
  else
    return text
  end
end

return Tokenizer
