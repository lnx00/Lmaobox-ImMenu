if UnloadLib ~= nil then UnloadLib() end

---@type boolean, LNXlib
local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")
assert(Lib.GetVersion() >= 0.94, "LNXlib version is too old, please update it!")

local Fonts, KeyHelper, Input = Lib.UI.Fonts, Lib.Utils.KeyHelper, Lib.Utils.Input

---@alias ImItemID string
---@alias ImWindow { X : integer, Y : integer, W : integer, H : integer }
---@alias ImFrame { X : integer, Y : integer, W : integer, H : integer, A : integer }
---@alias ImColor table<integer, integer, integer, integer?>
---@alias ImStyle any

---@class ImMenu
---@field public Cursor { X : integer, Y : integer }
---@field public ActiveItem ImItemID|nil
local ImMenu = {
    Cursor = { X = 0, Y = 0 },
    ActiveItem = nil
}

--[[ Variables ]]

-- Input Helpers
local MouseHelper = KeyHelper.new(MOUSE_LEFT)
local EnterHelper = KeyHelper.new(KEY_ENTER)

---@type table<string, ImWindow>
local Windows = {}

---@type table<ImColor>
local Colors = {
    Title = { 55, 100, 215, 255 },
    Text = { 255, 255, 255, 255 },
    Window = { 30, 30, 30, 255 },
    Item = { 50, 50, 50, 255 },
    ItemHover = { 60, 60, 60, 255 },
    ItemActive = { 70, 70, 70, 255 },
    Highlight = { 180, 180, 180, 100 },
    HighlightActive = { 240, 240, 240, 140 },
}

---@type table<ImStyle>
local Style = {
    Font = Fonts.Verdana,
    Spacing = 5,
    FramePadding = 7,
    ItemSize = 20,
    SameLine = false
}

-- Stacks
local WindowStack = Stack.new()
local FrameStack = Stack.new()
local ColorStack = Stack.new()
local StyleStack = Stack.new()

--[[ Private Functions ]]

---@param color ImColor
local function UnpackColor(color)
    color[4] = color[4] or 255
    return table.unpack(color)
end

--[[ Public Getters ]]

function ImMenu.GetStyle() return table.readOnly(Style) end
function ImMenu.GetColors() return table.readOnly(Colors) end
function ImMenu.GetCurrentWindow() return WindowStack:peek() end
function ImMenu.GetCurrentFrame() return FrameStack:peek() end

--[[ Public Setters ]]

---@param color ImColor
function ImMenu.SetNextColor(color)
    draw.Color(UnpackColor(color))
end

-- Push a color to the stack
---@param key string
---@param color ImColor
function ImMenu.PushColor(key, color)
    ColorStack:push({ Key = key, Value = Colors[key] })
    Colors[key] = color
end

-- Pop the last color from the stack
---@param amount? integer
function ImMenu.PopColor(amount)
    amount = amount or 1
    for _ = 1, amount do
        local color = ColorStack:pop()
        Colors[color.Key] = color.Value
    end
end

-- Push a style to the stack
---@param key string
---@param style ImStyle
function ImMenu.PushStyle(key, style)
    StyleStack:push({ Key = key, Value = Style[key] })
    Style[key] = style
end

-- Pop the last style from the stack
---@param amount? integer
function ImMenu.PopStyle(amount)
    amount = amount or 1
    for _ = 1, amount do
        local style = StyleStack:pop()
        Style[style.Key] = style.Value
    end
end

--[[ Public Functions ]]

-- Updates the cursor and current frame size
function ImMenu.UpdateCursor(w, h)
    local frame = ImMenu.GetCurrentFrame()
    if frame then
        if frame.A == 0 then
            ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.Spacing
            frame.W = math.max(frame.W, w)
            frame.H = math.max(frame.H, ImMenu.Cursor.Y - frame.Y)
        elseif frame.A == 1 then
            ImMenu.Cursor.X = ImMenu.Cursor.X + w + Style.Spacing
            frame.W = math.max(frame.W, ImMenu.Cursor.X - frame.X)
            frame.H = math.max(frame.H, h)
        end
    else
        -- TODO: Should it be allowed to draw without frames?
        ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.Spacing
    end
end

-- Updates the next color depending on the interaction state
---@param hovered boolean
---@param active boolean
function ImMenu.InteractionColor(hovered, active)
    if active then
        ImMenu.SetNextColor(Colors.ItemActive)
    elseif hovered then
        ImMenu.SetNextColor(Colors.ItemHover)
    else
        ImMenu.SetNextColor(Colors.Item)
    end
end

-- Returns whether the element is clicked or active
---@param x number
---@param y number
---@param width number
---@param height number
---@param id string
---@return boolean, boolean, boolean
function ImMenu.GetInteraction(x, y, width, height, id)
    local hovered = Input.MouseInBounds(x, y, x + width, y + height) or id == ImMenu.ActiveItem
    local clicked = hovered and (MouseHelper:Pressed() or EnterHelper:Pressed())
    local active = hovered and (MouseHelper:Down() or EnterHelper:Down())

    -- Is a different element active?
    if ImMenu.ActiveItem ~= nil and ImMenu.ActiveItem ~= id then
        return hovered, false, false
    end

    -- Should this element be active?
    if active and ImMenu.ActiveItem == nil then
        ImMenu.ActiveItem = id
    end

    -- Is this element no longer active?
    if ImMenu.ActiveItem == id and not active then
        ImMenu.ActiveItem = nil
    end

    return hovered, clicked, active
end

function ImMenu.DrawText(x, y, text)
    for label in text:gmatch("(.+)###(.+)") do
        draw.Text(x, y, label)
        return
    end

    draw.Text(x, y, text)
end

function ImMenu.BeginFrame(align)
    align = align or 0

    FrameStack:push({ X = ImMenu.Cursor.X, Y = ImMenu.Cursor.Y, W = 0, H = 0, A = align })

    -- Apply padding
    ImMenu.Cursor.X = ImMenu.Cursor.X + Style.FramePadding
    ImMenu.Cursor.Y = ImMenu.Cursor.Y + Style.FramePadding
end

function ImMenu.EndFrame()
    local frame = FrameStack:pop()

    ImMenu.Cursor.X = frame.X
    ImMenu.Cursor.Y = frame.Y

    -- Apply padding
    frame.W = frame.W + Style.FramePadding * 2
    frame.H = frame.H + Style.FramePadding * 2

    -- Update the cursor
    ImMenu.UpdateCursor(frame.W, frame.H)

    -- TODO: Remove this
    draw.Color(255, 0, 0, 50)
    draw.OutlinedRect(frame.X, frame.Y, frame.X + frame.W, frame.Y + frame.H)

    return frame
end

---@param title string
function ImMenu.Begin(title)
    if not Windows[title] then
        Windows[title] = {
            X = 50,
            Y = 150,
            W = 100,
            H = 100
        }
    end

    draw.SetFont(Style.Font)
    local window = Windows[title]
    local txtWidth, txtHeight = draw.GetTextSize(title)
    local titleHeight = txtHeight + Style.Spacing

    -- Title bar
    draw.Color(table.unpack(Colors.Title))
    draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H)
    draw.FilledRect(window.X, window.Y, window.X + window.W, window.Y + titleHeight)

    -- Title text
    draw.Color(table.unpack(Colors.Text))
    ImMenu.DrawText(window.X + (window.W // 2) - (txtWidth // 2), window.Y + (20 // 2) - (txtHeight // 2), title)

    -- Background
    draw.Color(table.unpack(Colors.Window))
    draw.FilledRect(window.X, window.Y + titleHeight, window.X + window.W, window.Y + window.H + titleHeight)

    ImMenu.Cursor.X = window.X
    ImMenu.Cursor.Y = window.Y + titleHeight

    ImMenu.BeginFrame()

    Windows[title] = window
    WindowStack:push(window)
end

function ImMenu.End()
    ---@type ImFrame
    local frame = ImMenu.EndFrame()
    local window = WindowStack:pop()
    window.W = math.max(window.W, frame.W)
    window.H = math.max(window.H, frame.H)
end

-- Draw a label
---@param text string
function ImMenu.Text(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = draw.GetTextSize(text)

    draw.Color(table.unpack(Colors.Text))
    ImMenu.DrawText(x, y, text)

    ImMenu.UpdateCursor(width, height)
end

-- Draws a checkbox that toggles a value
---@param text string
---@param state boolean
---@return boolean, boolean
function ImMenu.Checkbox(text, state)
    local x, y = ImMenu.Cursor.X + Style.Spacing, ImMenu.Cursor.Y
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local boxSize = txtHeight + Style.Spacing * 2
    local width, height = boxSize + Style.Spacing + txtWidth, boxSize
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Box
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + boxSize, y + boxSize)

    -- Check
    if state then
        ImMenu.SetNextColor(Colors.Highlight)
        draw.FilledRect(x + Style.Spacing, y + Style.Spacing, x + (boxSize - Style.Spacing), y + (boxSize - Style.Spacing))
    end

    -- Text
    ImMenu.SetNextColor(Colors.Text)
    ImMenu.DrawText(x + boxSize + Style.Spacing, y + (height // 2) - (txtHeight // 2), text)

    -- Update State
    if clicked then
        state = not state
    end

    ImMenu.UpdateCursor(width, height)
    return state, clicked
end

-- Draws a button
---@param text string
---@return boolean, boolean
function ImMenu.Button(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = txtWidth + Style.Spacing * 2, txtHeight + Style.Spacing * 2
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Text
    draw.Color(table.unpack(Colors.Text))
    ImMenu.DrawText(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), text)

    ImMenu.UpdateCursor(width, height)
    return clicked, active
end

return ImMenu
