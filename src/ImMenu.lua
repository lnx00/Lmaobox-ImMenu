--[[
    Immediate mode menu library for Lmaobox
    Author: github.com/lnx00
]]
if UnloadLib ~= nil then UnloadLib() end

-- Import lnxLib
---@type boolean, lnxLib
local libLoaded, lnxLib = pcall(require, "lnxLib")
assert(libLoaded, "lnxLib not found, please install it!")
assert(lnxLib.GetVersion() >= 0.94, "lnxLib version is too old, please update it!")

local Fonts, Notify = lnxLib.UI.Fonts, lnxLib.UI.Notify
local KeyHelper, Input, Timer = lnxLib.Utils.KeyHelper, lnxLib.Utils.Input, lnxLib.Utils.Timer

-- Annotation aliases
---@alias ImItemID string
---@alias ImPos { X : integer, Y : integer }
---@alias ImWindow { X : integer, Y : integer, W : integer, H : integer }
---@alias ImFrame { X : integer, Y : integer, W : integer, H : integer, A : integer }
---@alias ImColor table<integer, integer, integer, integer?>
---@alias ImStyle any

--[[ Globals ]]
---@enum ImAlign
ImAlign = { Vertical = 0, Horizontal = 1 }

---@class ImMenu
---@field public Cursor ImPos
---@field public ActiveItem ImItemID|nil
local ImMenu = {
    Cursor = { X = 0, Y = 0 },
    ActiveItem = nil,
    ActivePopup = nil
}

--[[ Variables ]]
local screenWidth, screenHeight = draw.GetScreenSize()
local dragPos = { X = 0, Y = 0 }
local lastKey = { Key = 0, Time = 0 }
local inPopup = false

-- Input Helpers
local MouseHelper = KeyHelper.new(MOUSE_LEFT)
local EnterHelper = KeyHelper.new(KEY_ENTER)
local LeftArrow = KeyHelper.new(KEY_LEFT)
local RightArrow = KeyHelper.new(KEY_RIGHT)

---@type table<string, ImWindow>
local Windows = {}

---@type function[]
local LateDrawList = {}

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
    FrameBorder = { 0, 0, 0, 200 },
    Border = { 0, 0, 0, 200 }
}

---@type ImStyle[]
local Style = {
    Font = Fonts.Verdana,
    ItemPadding = 5,
    ItemMargin = 5,
    FramePadding = 5,
    ItemSize = nil,
    WindowBorder = true,
    FrameBorder = false,
    ButtonBorder = false,
    CheckboxBorder = false,
    SliderBorder = false,
    Border = false,
    Popup = false
}

-- Stacks
local WindowStack = Stack.new()
local FrameStack = Stack.new()
local ColorStack = Stack.new()
local StyleStack = Stack.new()

--[[ Private Functions ]]
---@param color ImColor
local function UnpackColor(color)
    return color[1], color[2], color[3], color[4] or 255
end

---@return integer?
local function GetInput()
    local key = Input.GetPressedKey()
    if not key then
        lastKey.Key = 0
        return nil
    end

    if key < KEY_0 or key > KEY_TAB then
        return nil
    end

    if key == lastKey.Key then
        if lastKey.Time + 0.5 < globals.RealTime() then
            return key
        else
            return nil
        end
    end

    lastKey.Key = key
    lastKey.Time = globals.RealTime()
    return key
end

--[[ Public Getters ]]

---@return number
function ImMenu.GetVersion() return 0.66 end

---@return ImStyle[]
function ImMenu.GetStyle() return table.readOnly(Style) end

---@return ImColor[]
function ImMenu.GetColors() return table.readOnly(Colors) end

---@return ImWindow
function ImMenu.GetCurrentWindow() return WindowStack:peek() end

---@return ImFrame
function ImMenu.GetCurrentFrame() return FrameStack:peek() end

--[[ Public Setters ]]
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
-- Creates a new color attribute
---@param key string
---@param value any
function ImMenu.AddColor(key, value)
    Colors[key] = value
end

-- Creates a new style attribute
---@param key string
---@param value any
function ImMenu.AddStyle(key, value)
    Style[key] = value
end

-- Runs all late draw functions
function ImMenu.LateDraw()
    draw.Color(255, 255, 255, 255)

    -- Run all late draw functions
    for _, func in ipairs(LateDrawList) do
        func()
    end

    LateDrawList = {}
end

-- Updates the cursor and current frame size
---@param w integer
---@param h integer
function ImMenu.UpdateCursor(w, h)
    local frame = ImMenu.GetCurrentFrame()
    if frame then
        if frame.A == 0 then
            -- Horizontal
            ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.ItemMargin
            frame.W = math.max(frame.W, w)
            frame.H = math.max(frame.H, ImMenu.Cursor.Y - frame.Y)
        elseif frame.A == 1 then
            -- Vertical
            ImMenu.Cursor.X = ImMenu.Cursor.X + w + Style.ItemMargin
            frame.W = math.max(frame.W, ImMenu.Cursor.X - frame.X)
            frame.H = math.max(frame.H, h)
        end
    else
        -- TODO: It shouldn't be allowed to draw outside of a frame
        ImMenu.Cursor.Y = ImMenu.Cursor.Y + h + Style.ItemMargin
    end
end

-- Updates the next color depending on the interaction state
---@param hovered boolean
---@param active boolean
function ImMenu.InteractionColor(hovered, active)
    if active then
        draw.Color(UnpackColor(Colors.ItemActive))
    elseif hovered then
        draw.Color(UnpackColor(Colors.ItemHover))
    else
        draw.Color(UnpackColor(Colors.Item))
    end
end

---@param width integer
---@param height integer
---@return integer width, integer height
function ImMenu.GetSize(width, height)
    if Style.ItemSize ~= nil then
        width, height = Style.ItemSize[1], Style.ItemSize[2]
    end

    return width, height
end

-- Returns whether the element is clicked or active
---@param x number
---@param y number
---@param width number
---@param height number
---@param id string
---@return boolean hovered, boolean clicked, boolean active
function ImMenu.GetInteraction(x, y, width, height, id)
    -- Is a different element active?
    if ImMenu.ActiveItem ~= nil and ImMenu.ActiveItem ~= id then
        return false, false, false
    end

    -- Is a popup active?
    if ImMenu.ActivePopup ~= nil and not inPopup then
        return false, false, false
    end

    local hovered = Input.MouseInBounds(x, y, x + width, y + height) or id == ImMenu.ActiveItem
    local clicked = hovered and (MouseHelper:Pressed() or EnterHelper:Pressed())
    local active = hovered and (MouseHelper:Down() or EnterHelper:Down())

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

---@param text string
function ImMenu.GetLabel(text)
    for label in text:gmatch("(.+)###(.+)") do
        return label
    end

    return text
end

---@param size? number
function ImMenu.Space(size)
    size = size or Style.ItemMargin
    ImMenu.UpdateCursor(size, size)
end

function ImMenu.Separator()
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local width, height = ImMenu.GetSize(250, Style.ItemMargin * 2)

    draw.Color(UnpackColor(Colors.WindowBorder))
    draw.Line(x, y + height // 2, x + width, y + height // 2)

    ImMenu.UpdateCursor(width, height)
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
---@return ImFrame frame
function ImMenu.EndFrame()
    ---@type ImFrame
    local frame = FrameStack:pop()

    ImMenu.Cursor.X = frame.X
    ImMenu.Cursor.Y = frame.Y

    -- Apply padding
    if frame.A == 0 then
        -- Horizontal
        frame.W = frame.W + Style.FramePadding * 2
        frame.H = frame.H + Style.FramePadding - Style.ItemMargin
    elseif frame.A == 1 then
        -- Vertical
        frame.H = frame.H + Style.FramePadding * 2
        frame.W = frame.W + Style.FramePadding - Style.ItemMargin
    end

    -- Border
    if Style.FrameBorder then
        draw.Color(UnpackColor(Colors.FrameBorder))
        draw.OutlinedRect(frame.X, frame.Y, frame.X + frame.W, frame.Y + frame.H)
    end

    -- Update the cursor
    ImMenu.UpdateCursor(frame.W, frame.H)

    return frame
end

-- Begins a new window
---@param title string
---@param visible? boolean
---@return boolean visible
function ImMenu.Begin(title, visible)
    local isVisible = (visible == nil) or visible
    if not isVisible then return false end

    -- Create the window if it doesn't exist
    if not Windows[title] then
        Windows[title] = {
            X = 50,
            Y = 150,
            W = 100,
            H = 100
        }
    end

    -- Initialize the window
    draw.SetFont(Style.Font)
    local window = Windows[title]
    local titleText = ImMenu.GetLabel(title)
    local txtWidth, txtHeight = draw.GetTextSize(titleText)
    local titleHeight = txtHeight + Style.ItemPadding
    local hovered, clicked, active = ImMenu.GetInteraction(window.X, window.Y, window.W, titleHeight, title)

    -- Title bar
    draw.Color(table.unpack(Colors.Title))
    draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H)
    draw.FilledRect(window.X, window.Y, window.X + window.W, window.Y + titleHeight)

    -- Title text
    draw.Color(table.unpack(Colors.Text))
    draw.Text(window.X + (window.W // 2) - (txtWidth // 2), window.Y + (20 // 2) - (txtHeight // 2), titleText)

    -- Background
    draw.Color(table.unpack(Colors.Window))
    draw.FilledRect(window.X, window.Y + titleHeight, window.X + window.W, window.Y + window.H + titleHeight)

    -- Border
    if Style.WindowBorder then
        draw.Color(UnpackColor(Colors.WindowBorder))
        draw.OutlinedRect(window.X, window.Y, window.X + window.W, window.Y + window.H + titleHeight)
        draw.Line(window.X, window.Y + titleHeight, window.X + window.W, window.Y + titleHeight)
    end

    -- Mouse drag
    if active then
        local mX, mY = table.unpack(input.GetMousePos())
        if clicked then
            dragPos = { X = mX - window.X, Y = mY - window.Y }
        end

        window.X = math.clamp(mX - dragPos.X, 0, screenWidth - window.W)
        window.Y = math.clamp(mY - dragPos.Y, 0, screenHeight - window.H - titleHeight)
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
---@return ImWindow
function ImMenu.End()
    ---@type ImFrame
    local frame = ImMenu.EndFrame()
    local window = WindowStack:pop()

    -- Update the window size
    window.W = frame.W
    window.H = frame.H

    -- Draw late draw list
    ImMenu.LateDraw()

    return window
end

-- Runs the given function after the current window has been drawn
function ImMenu.DrawLate(func)
    table.insert(LateDrawList, func)
end

---@param x integer
---@param y integer
---@param func function
function ImMenu.Popup(x, y, func)
    ImMenu.DrawLate(function()
        inPopup = true

        -- Prepare cursor
        ImMenu.Cursor.X = x
        ImMenu.Cursor.Y = y

        -- Draw the popup | TODO: Add a popup frame background
        ImMenu.PushStyle("FramePadding", 0)
        ImMenu.PushStyle("ItemMargin", 0)
        ImMenu.BeginFrame()
        func()
        local frame = ImMenu.EndFrame()
        ImMenu.PopStyle(2)

        -- Close the popup if clicked outside of it
        if not Input.MouseInBounds(frame.X, frame.Y, frame.X + frame.W, frame.Y + frame.H) and MouseHelper:Pressed() then
            ImMenu.ActivePopup = nil
        end

        inPopup = false
    end)
end

-- Draw a label
---@param text string
function ImMenu.Text(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(txtWidth, txtHeight)

    draw.Color(table.unpack(Colors.Text))
    draw.Text(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), label)

    ImMenu.UpdateCursor(width, height)
end

-- Draws a checkbox that toggles a value
---@param text string
---@param state boolean
---@return boolean state, boolean clicked
function ImMenu.Checkbox(text, state)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local boxSize = txtHeight + Style.ItemPadding * 2
    local width, height = ImMenu.GetSize(boxSize + Style.ItemMargin + txtWidth, boxSize)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Box
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + boxSize, y + boxSize)

    -- Border
    if Style.CheckboxBorder then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + boxSize, y + boxSize)
    end

    -- Check
    if state then
        draw.Color(UnpackColor(Colors.Highlight))
        draw.FilledRect(x + Style.ItemPadding, y + Style.ItemPadding, x + (boxSize - Style.ItemPadding),
        y + (boxSize - Style.ItemPadding))
    end

    -- Text
    draw.Color(UnpackColor(Colors.Text))
    draw.Text(x + boxSize + Style.ItemMargin, y + (height // 2) - (txtHeight // 2), label)

    -- Update State
    if clicked then
        state = not state
    end

    ImMenu.UpdateCursor(width, height)
    return state, clicked
end

-- Draws a button
---@param text string
---@return boolean clicked, boolean active
function ImMenu.Button(text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = ImMenu.GetLabel(text)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(txtWidth + Style.ItemPadding * 2, txtHeight + Style.ItemPadding * 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    if Style.ButtonBorder then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Text
    draw.Color(table.unpack(Colors.Text))
    draw.Text(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), label)

    if clicked then
        ImMenu.ActiveItem = nil
    end

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
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    ImMenu.UpdateCursor(width, height)
end

-- Draws a slider that changes a value
---@param text string
---@param value number
---@param min number
---@param max number
---@param step? number
---@return number value, boolean clicked
function ImMenu.Slider(text, value, min, max, step)
    step = step or 1
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local label = string.format("%s: %s", ImMenu.GetLabel(text), value)
    local txtWidth, txtHeight = draw.GetTextSize(label)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)
    local sliderWidth = math.floor(width * (value - min) / (max - min))
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, text)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Slider
    draw.Color(UnpackColor(Colors.Highlight))
    draw.FilledRect(x, y, x + sliderWidth, y + height)

    -- Border
    if Style.SliderBorder then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    -- Text
    draw.Color(UnpackColor(Colors.Text))
    draw.Text(x + (width // 2) - (txtWidth // 2), y + (height // 2) - (txtHeight // 2), label)

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
    local width, height = ImMenu.GetSize(250, 15)
    local progressWidth = math.floor(width * (value - min) / (max - min))

    -- Background
    draw.Color(UnpackColor(Colors.Item))
    draw.FilledRect(x, y, x + width, y + height)

    -- Progress
    draw.Color(UnpackColor(Colors.Highlight))
    draw.FilledRect(x, y, x + progressWidth, y + height)

    -- Border
    if Style.Border then
        draw.Color(UnpackColor(Colors.Border))
        draw.OutlinedRect(x, y, x + width, y + height)
    end

    ImMenu.UpdateCursor(width, height)
end

---@param label string
---@param text string
---@return string text
function ImMenu.TextInput(label, text)
    local x, y = ImMenu.Cursor.X, ImMenu.Cursor.Y
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)
    local txtY = y + (height // 2) - (txtHeight // 2)
    local hovered, clicked, active = ImMenu.GetInteraction(x, y, width, height, label)

    -- Background
    ImMenu.InteractionColor(hovered, active)
    draw.FilledRect(x, y, x + width, y + height)

    -- Border
    draw.Color(UnpackColor(Colors.Border))
    draw.OutlinedRect(x, y, x + width, y + height)

    -- Text
    draw.Color(UnpackColor(Colors.Text))
    if txtWidth > width - 2 * Style.ItemPadding then
        local charWidth = math.ceil(txtWidth / #text)
        local charCount = (width // charWidth) - 2
        draw.Text(x + Style.ItemPadding, txtY, string.sub(text, -charCount))
    else
        draw.Text(x + Style.ItemPadding, txtY, text)
    end

    -- Cursor
    if hovered then
        draw.Color(UnpackColor(Colors.Highlight))
        local cursorX = math.min(x + txtWidth, x + width - Style.ItemPadding * 2)
        draw.FilledRect(cursorX + Style.ItemPadding, txtY, cursorX + Style.ItemPadding + 2, txtY + txtHeight)
    end

    -- Text Input
    if hovered then
        local key = GetInput()
        if key then
            if key == KEY_BACKSPACE then
                text = text:sub(1, -2)
            elseif key == KEY_SPACE then
                text = text .. " "
            elseif key == KEY_TAB then
                text = text .. "\t"
            else
                local char = Input.KeyToChar(key)
                if char then
                    if input.IsButtonDown(KEY_LSHIFT) then
                        char = char:upper()
                    else
                        char = char:lower()
                    end
                    text = text .. char
                end
            end
        end
    end

    ImMenu.UpdateCursor(width, height)
    return text
end

---@param selected integer
---@param options any[]
---@return integer selected
function ImMenu.Option(selected, options)
    local txtWidth, txtHeight = draw.GetTextSize("#")
    local btnSize = txtHeight + 2 * Style.ItemPadding
    local width, height = ImMenu.GetSize(250, txtHeight)

    ImMenu.PushStyle("ItemSize", { btnSize, btnSize })
    ImMenu.PushStyle("FramePadding", 0)
    ImMenu.BeginFrame(1)

    -- Last Item button
    if ImMenu.Button("<###" .. tostring(options)) then
        selected = ((selected - 2) % #options) + 1
    end

    -- Current Item
    ImMenu.PushStyle("ItemSize", { width - (2 * btnSize) - (2 * Style.ItemMargin), btnSize })
    ImMenu.Text(tostring(options[selected]))
    ImMenu.PopStyle()

    -- Next Item button
    if ImMenu.Button(">###" .. tostring(options)) then
        selected = (selected % #options) + 1
    end

    ImMenu.EndFrame()
    ImMenu.PopStyle(2)

    return selected
end

---@param text string
---@param items string[]
function ImMenu.List(text, items)
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)

    ImMenu.PushStyle("FramePadding", 0)
    ImMenu.PushStyle("ItemSize", { width, height })
    ImMenu.BeginFrame()

    -- Title
    ImMenu.Text(text)

    -- Items
    for _, item in ipairs(items) do
        ImMenu.Button(tostring(item))
    end

    ImMenu.EndFrame()
    ImMenu.PopStyle(2)
end

---@param text string
---@param selected integer
---@param options string[]
function ImMenu.Combo(text, selected, options)
    local txtWidth, txtHeight = draw.GetTextSize(text)
    local width, height = ImMenu.GetSize(250, txtHeight + Style.ItemPadding * 2)

    -- Dropdown button
    ImMenu.PushStyle("ItemSize", { width, height })
    if ImMenu.Button(text) then
        ImMenu.ActivePopup = text
    end

    -- Dropdown popup
    if ImMenu.ActivePopup == text then
        ImMenu.Popup(ImMenu.Cursor.X, ImMenu.Cursor.Y, function()
            ImMenu.PushStyle("ItemSize", { width, height })

            for i, option in ipairs(options) do
                if ImMenu.Button(tostring(option)) then
                    selected = i
                    ImMenu.ActivePopup = nil
                end
            end

            ImMenu.PopStyle(1)
        end)
    end

    ImMenu.PopStyle()

    return selected
end

---@param tabs string[]
---@param currentTab integer
---@return integer currentTab
function ImMenu.TabControl(tabs, currentTab)
    ImMenu.PushStyle("FramePadding", 0)
    ImMenu.PushStyle("ItemSize", { 100, 25 })
    ImMenu.PushStyle("Spacing", 0)
    ImMenu.BeginFrame(1)

    -- Items
    for i, item in ipairs(tabs) do
        if ImMenu.Button(tostring(item)) then
            currentTab = i
        end
    end

    ImMenu.EndFrame()
    ImMenu.PopStyle(3)

    return currentTab
end

lnxLib.UI.Notify.Simple("ImMenu loaded", string.format("Version: %.2f", ImMenu.GetVersion()))

return ImMenu
