---@type ImMenu
local ImMenu = require("ImMenu")

---@alias ImFile { name: string, attributes: integer }

local currentPath = "tf/"
local currentOffset = 1

---@return ImFile[]
local function GetFileList(path)
    local files = {}

    filesystem.EnumerateDirectory(path .. "*", function (filename, attributes)
        table.insert(files, { name = filename, attributes = attributes })
    end)

    return files
end

function ImMenu.FileBrowser()
    if ImMenu.Begin("File Browser", true) then
        
        -- Navigation bar
        ImMenu.BeginFrame(ImAlign.Horizontal)
            ImMenu.Text("Path: tf/")
        ImMenu.EndFrame()

        -- Content
        ImMenu.BeginFrame(ImAlign.Horizontal)

            -- Navigation
            ImMenu.PushStyle("ItemSize", { 25, 50 })
            ImMenu.BeginFrame(ImAlign.Vertical)
                if ImMenu.Button("^") then
                    currentOffset = math.max(currentOffset - 1, 1)
                end
                if ImMenu.Button("v") then
                    currentOffset = currentOffset + 1
                end
            ImMenu.EndFrame()
            ImMenu.PopStyle()

            -- File list
            ImMenu.PushStyle("ItemSize", { 300, 25 })
            ImMenu.BeginFrame(ImAlign.Vertical)
                local fileList = GetFileList(currentPath)
                for i = currentOffset, currentOffset + 10 do
                    local file = fileList[i]
                    if file then
                        local isFolder = file.attributes == 16
                        if isFolder then
                            if ImMenu.Button(file.name .. "/") then
                                if file.attributes == 16 then
                                    currentPath = currentPath .. file.name .. "/"
                                    currentOffset = 1
                                end
                            end
                        else
                            ImMenu.Button(file.name)
                        end
                    end
                end
            ImMenu.EndFrame()
            ImMenu.PopStyle()

        ImMenu.EndFrame()

        ImMenu.End()
    end
end