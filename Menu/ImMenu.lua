if UnloadLib ~= nil then UnloadLib() end

---@type boolean, LNXlib
local libLoaded, Lib = pcall(require, "LNXlib")
assert(libLoaded, "LNXlib not found, please install it!")
assert(Lib.GetVersion() >= 0.94, "LNXlib version is too old, please update it!")

local Fonts, KeyHelper, Input = Lib.UI.Fonts, Lib.Utils.KeyHelper, Lib.Utils.Input

---@alias ImItemID string
---@alias ImPos { X : integer, Y : integer }
---@alias ImRect { X : integer, Y : integer, W : integer, H : integer }
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

local ScreenWidth, ScreenHeight = draw.GetScreenSize()
---@type ImPos
local DragPos = { X = 0, Y = 0 }

-- Input Helpers
local MouseHelper = KeyHelper.new(MOUSE_LEFT)
local EnterHelper = KeyHelper.new(KEY_ENTER)
local LeftArrow = KeyHelper.new(KEY_LEFT)
local RightArrow = KeyHelper.new(KEY_RIGHT)

---@type table<string, ImRect>
local Windows = {}

---@type ImColor[]
local Colors = {
    Title = { 55, 100, 215, 255 },
    Text = { 255, 255, 255, 255 },
    Window = { 30, 30, 30, 255 },
    Item = { 50, 50, 50, 255 },
    ItemHover = { 60, 60, 60, 255 },
    ItemActive = { 70, 70, 70, 255 },
    Highlight = { 180, 180, 180, 100 },
    HighlightActive = { 240, 240, 240, 140 },
    WindowBorder = { 55, 100, 215, 255 },
    Border = { 0, 0, 0, 200 }
}

---@type ImStyle[]
local Style = {
    Font = Fonts.Verdana,
    Spacing = 5,
    FramePadding = 7,
    ItemSize = nil,
    WindowBorder = false,
    ButtonBorder = false,
    CheckboxBorder = false,
    SliderBorder = false,
    Border = false
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

function ImMenu.GetVersion() return 0.53 end
function ImMenu.GetStyle() return table.readOnly(Style) end
function ImMenu.GetColors() return table.readOnly(Colors) end

---@return ImRect
function ImMenu.GetCurrentWindow() return WindowStack:peek() end

---@return ImFrame
function ImMenu.GetCurrentFrame() return FrameStack:peek() end

--[[ Public Setters ]]

---@param color ImColor
function ImMenu.SetColor(color)
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
        ImMenu.SetColor(Colors.ItemActive)
    elseif hovered then
        ImMenu.SetColor(Colors.ItemHover)
    else
        ImMenu.SetColor(Colors.Item)
    end
end

---@param width integer
---@param height integer
---@return integer, integer
function ImMenu.GetSize(width, height)
    if Style.ItemSize ~= nil then
        local frame = ImMenu.GetCurrentFrame()
        width = Style.ItemSize[1] == -1 and frame.W or Style.ItemSize[1]
        height = Style.ItemSize[2] == -1 and frame.H or Style.ItemSize[2]
    end

    return width, height
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

---@param x integer
---@param y integer
---@param text string
function ImMenu.DrawText(x, y, text)
    for label in text:gmatch("(.+)###(.+)") do
        draw.Text(x, y, label)
        return
    end

    draw.Text(x, y, text)
end

-- Begins a new frame
---@param align? integer
function ImMenu.BeginFrame(align)
    align = align or 0

    FrameStack:push({ X = ImMenu.Cursor.X, Y = ImMenu.Cursor.Y, W = 0, H = 0, A = align })

    -- Apply padding
    ImMenu.Cursor.X = ImMenu.Cursor.X + Style.FramePadding
    ImMenu.Cursor.Y = ImMenu.Cursor.Y + Style.FramePadding
end

-- Ends the current frame
---@return ImFrame
function ImMenu.EndFrame()
    ---@type ImFrame
    local frame = FrameStack:pop()

    ImMenu.Cursor.X = frame.X
    ImMenu.Cursor.Y = frame.Y

    -- Apply padding
    if frame.A == 0 then
        frame.W = frame.W + Style.FramePadding * 2
    elseif frame.A == 1 then
        frame.H = frame.H + Style.FramePadding * 2
    end

    -- Update the cursor
    ImMenu.UpdateCursor(frame.W, frame.H)

    -- TODO: Remove this
    --draw.Color(255, 0, 0, 50)
    --draw.OutlinedRect(frame.X, frame.Y, frame.X + frame.W, frame.Y + frame.H)

    return frame
end

-- Begins a new window
---@param title string
---@param visible? boolean
function ImMenu.Begin(title, visible)
    local isVisible = (visible == nil) or visible
    if not isVisible then return false end

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
    local hovered, clicked, active = ImMenu.GetInteraction(window.X, window.Y, window.W, titleHeight, title)

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

    -- Border
    if Style.WindowBorder then
        ImMenu.SetColor(Colors.WindowBorder)
        draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H + titleHeight)
        draw.Line(window.X, window.Y + titleHeight, window.X + window.W, window.Y + titleHeight)
    end

    -- Mouse drag
    if active then
        local mX, mY = table.unpack(input.GetMousePos())
        if clicked then
            DragPos = { X = mX - window.X, Y = mY - window.Y }
        end

        window.X = math.clamp(mX - DragPos.X, 0, ScreenWidth - window.W)
        window.Y = math.clamp(mY - DragPos.Y, 0, ScreenHeight - window.H - titleHeight)
    end

    -- Update the cursor
    ImMenu.Cursor.X = window.X
    ImMenu.Cursor.Y = window.Y + titleHeight

    ImMenu.BeginFrame()

    -- Store and pish the window
    Windows[title] = window
    WindowStack:push(window)

    return true
end

-- Ends the current window
function ImMenu.End()
    ---@type ImFrame
    local frame = ImMenu.EndFrame()
    local window = WindowStack:pop()

    -- Update the window size
    window.W = frame.W
    window.H = frame.H
end

-- Draw a label
---@param text string
function ImMenu.Text(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = ImMenu.GetSize(draw.GetTextSize(text))

    draw.Color(table.unpack(Colors.Text))
    ImMenu.DrawText(x, y, text)

    ImMenu.UpdateCursor(width, height)
end

-- Draws a checkbox that toggles a value
---@param text string
---@param state boolean
---@return boolean, boolean
function ImMenu.Checkbox(text, state)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local boxSize = txtHeight + Style.Spacing * 2
    local width, height = ImMenu.GetSize(boxSize + Style.Spacing + txtWidth, boxSize)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Box
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + boxSize, y + boxSize)

    -- Border
    if Style.CheckboxBorder then
        ImMenu.SetColor(Colors.Border)
        draw.OutlinedRect(x, y, x + boxSize, y + boxSize)
    end

    -- Check
    if state then
        ImMenu.SetColor(Colors.Highlight)
        draw.FilledRect(x + Style.Spacing, y + Style.Spacing, x + (boxSize - Style.Spacing), y + (boxSize - Style.Spacing))
    end

    -- Text
    ImMenu.SetColor(Colors.Text)
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
    local width, height = ImMenu.GetSize(txtWidth + Style.Spacing * 2, txtHeight + Style.Spacing * 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    if Style.ButtonBorder then
        ImMenu.SetColor(Colors.Border)
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Text
    draw.Color(table.unpack(Colors.Text))
    ImMenu.DrawText(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), text)

    ImMenu.UpdateCursor(width, height)
    return clicked, active
end

---@param id Texture
function ImMenu.Texture(id)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = ImMenu.GetSize(draw.GetTextureSize(id))

    draw.Color(255, 255, 255, 255)
    draw.TexturedRect(id, x, y, x + width, y + height)

    if Style.Border then
        ImMenu.SetColor(Colors.Border)
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    ImMenu.UpdateCursor(width, height)
end

-- Draws a slider that changes a value
---@param text string
---@param value number
---@param min number
---@param max number
---@param step number
---@return number, boolean
function ImMenu.Slider(text, value, min, max, step)
    step = step or 1
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local valText = string.format("%s: %s", text, value)
    local txtWidth, txtHeight = draw.GetTextSize(valText)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.Spacing * 2)
    local sliderWidth = math.floor(width * (value - min) / (max - min))
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Slider
    ImMenu.SetColor(Colors.Highlight)
    draw.FilledRect(x, y, x + sliderWidth, y + height)

    -- Border
    if Style.SliderBorder then
        ImMenu.SetColor(Colors.Border)
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Text
    ImMenu.SetColor(Colors.Text)
    ImMenu.DrawText(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), valText)

    -- Update Value
    if active then
        -- Mouse drag
        local mX, mY = table.unpack(input.GetMousePos())
        local percent = math.clamp((mX - x) / width, 0, 1)
        value = math.round((min + (max - min) * percent) / step) * step
    elseif hovered then
        -- Arrow keys
        if LeftArrow:Pressed() then
            value = math.max(value - step, min)
        elseif RightArrow:Pressed() then
            value = math.min(value + step, max)
        end
    end

    ImMenu.UpdateCursor(width, height)
    return value, clicked
end

-- Draws a progress bar
---@param value number
---@param min number
---@param max number
function ImMenu.Progress(value, min, max)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = ImMenu.GetSize(250, 20)
    local progressWidth = math.floor(width * (value - min) / (max - min))

    -- Background
    ImMenu.SetColor(Colors.Item)
    draw.FilledRect(x, y, x + width, y + height)

    -- Progress
    ImMenu.SetColor(Colors.Highlight)
    draw.FilledRect(x, y, x + progressWidth, y + height)

    -- Border
    if Style.Border then
        ImMenu.SetColor(Colors.Border)
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    ImMenu.UpdateCursor(width, height)
end

---@param text string
---@param items string[]
function ImMenu.List(text, items)
    ImMenu.BeginFrame()

    ImMenu.Text(text)
    ImMenu.PushStyle("ItemSize", { 250, 30 })
    
    for _, item in ipairs(items) do
        ImMenu.Button(tostring(item))
    end

    ImMenu.PopStyle()
    ImMenu.EndFrame()
end

---@param size number
function ImMenu.Space(size)
    size = size or Style.Spacing
    ImMenu.UpdateCursor(size, size)
end

return ImMenu
