---@class Marker
---@field extMarks TidalExtMarks -- eventId -> col -> ExtMark
local Marker = {}

---@class TidalWordRanges
---@field range_start integer
---@field range_end integer
---@field function_name string
---@field quote_index integer
---

---@class TidalExtMark
---@field id? string
---@field buf integer
---@field markerId integer
---@field colStart integer
---@field colEnd integer
---@field row integer
---@field functionName string
---@field quoteIndex integer
---@field originalText string
---@field whole? TidalWhole

---@alias TidalExtMarkMap table<string, TidalExtMark>
---@alias TidalExtMarks table<integer, TidalExtMarkMap>
---
---
Marker.extMarks = {}
Marker.removeCandidates = {}

Marker.ns = vim.api.nvim_create_namespace("tidalEventHighlighting")

---Create all properties and metadata for ext marks
---@param ranges table
---@param lineNumber integer
---@param eventId integer
function Marker.createMarkers(ranges, lineNumber, eventId)
  local curr_buf = vim.api.nvim_get_current_buf()

  Marker.extMarks = Marker.extMarks or {}
  Marker.extMarks[eventId] = Marker.extMarks[eventId] or {}

  for _, value in ipairs(ranges) do
    if value.range_start > 0 then
      local row = (value.row ~= nil) and value.row or (lineNumber - 1)

      local line_text = vim.api.nvim_buf_get_lines(curr_buf, row, row + 1, false)[1] or ""
      local line_len = #line_text
      local safe_end_col = math.min(value.range_end, line_len)

      local markerId = vim.api.nvim_buf_set_extmark(curr_buf, Marker.ns, row, value.range_start - 1, {
        end_row = row,
        end_col = safe_end_col,
      })

      local originalText = vim.api.nvim_buf_get_text(
        curr_buf,
        row,
        value.range_start - 1,
        row,
        safe_end_col,
        {}
      )[1] or ""

      local extmark = {
        buf = curr_buf,
        markerId = markerId,
        colStart = value.range_start - 1,
        colEnd = value.range_end,
        row = row,
        functionName = value.function_name,
        quoteIndex = value.quote_index,
        originalText = originalText,
      }

      Marker.extMarks[eventId][row] = Marker.extMarks[eventId][row] or {}

      -- Keep the real span on the extmark (colStart..colEnd),
      -- but index the same extmark by every 1-based column in that span.
      for col = value.range_start, value.range_end do
        Marker.extMarks[eventId][row][col] = extmark
      end
    end
  end
end

function Marker.countNsExtmarks()
  local count = 0
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      -- get all extmarks in this buffer for this namespace
      local marks = vim.api.nvim_buf_get_extmarks(buf, Marker.ns, 0, -1, {})
      count = count + #marks
    end
  end

  return count
end

local function each_extmark(fn)
  if not Marker.extMarks then
    return
  end

  for eventId, rows in pairs(Marker.extMarks) do
    for row, cols in pairs(rows) do
      for col, extmark in pairs(cols) do
        fn(eventId, row, col, extmark)
      end
    end
  end
end

--- Debug function to count all created extmarks
function Marker.count()
  local n = 0

  each_extmark(function(_, _, _, _)
    n = n + 1
  end)

  return n
end

--- Debug function to print all created extmarks information
function Marker.print()
  each_extmark(function(eventId, row, col, extmark)
    print(
      "MarkerId: "
      .. extmark.markerId
      .. " | eventId: "
      .. eventId
      .. " | Row: "
      .. row
      .. " | colStart: "
      .. extmark.colStart
      .. " | colEnd: "
      .. extmark.colEnd
      .. " | loopCol: "
      .. col
      .. " | functionName: "
      .. extmark.functionName
    )
  end)
end

function Marker.deleteAllMarkers()
  -- Wiping complete namespace
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      vim.api.nvim_buf_clear_namespace(buf, Marker.ns, 0, -1)
    end
  end

  Marker.removeCandidates = {}
  Marker.extMarks = {} -- eventId -> col -> ExtMark
end

---Remove all markers within a given row range
---@param startRow integer
---@param endRow integer
function Marker.setRemovables(startRow, endRow)
  local seen = {}

  each_extmark(function(eventId, row, col, extmark)
    local oldMarker = vim.api.nvim_buf_get_extmark_by_id(extmark.buf, Marker.ns, extmark.markerId, {})

    if oldMarker ~= nil then
      local markerRow = oldMarker[1] + 1

      if markerRow >= startRow and markerRow <= endRow then
        if not seen[extmark.markerId] then
          seen[extmark.markerId] = true
          table.insert(Marker.removeCandidates, {
            eventId = eventId,
            row = row,
            col = col,
            buf = extmark.buf,
            ns = Marker.ns,
            markerId = extmark.markerId,
          })
        end
      end
    end
  end)
end

---Remove all markers within a given row range
function Marker.cleanUpMarkers()
  for _, extmark in ipairs(Marker.removeCandidates) do
    vim.api.nvim_buf_del_extmark(extmark.buf, extmark.ns, extmark.markerId)

    if Marker.extMarks[extmark.eventId] and Marker.extMarks[extmark.eventId][extmark.row] then
      for col, indexed in pairs(Marker.extMarks[extmark.eventId][extmark.row]) do
        if indexed.markerId == extmark.markerId then
          Marker.extMarks[extmark.eventId][extmark.row][col] = nil
        end
      end

      if next(Marker.extMarks[extmark.eventId][extmark.row]) == nil then
        Marker.extMarks[extmark.eventId][extmark.row] = nil
      end
    end

    if Marker.extMarks[extmark.eventId] and next(Marker.extMarks[extmark.eventId]) == nil then
      Marker.extMarks[extmark.eventId] = nil
    end
  end

  Marker.removeCandidates = {}
end

return Marker
