local shell = require("shell")
local filesystem = require("filesystem")
local internet = require("internet")

local repo = "https://raw.githubusercontent.com/hxync/BeeMasterXXL/"
local branch = "main"
local paths = { "lib" }

local scripts = {
    "strategy.lua",
    "config.lua",
    "bee.lua",
    "analyzeGenes.lua",
    "beeData.lua",
    "bot.lua",
    "doUntil.lua",
    "environment.lua",
    "tools.lua",
    "biomes.lua",
    "mutations.lua",
    "device.lua",
    "apiary.lua",
    "lib/inflate-bwo.lua",
    "lib/nbt.lua",
    "lib/zzlib.lua"
}

local function download(url)
    local handle = internet.request(url)
    local result = ""
    for chunk in handle do
        result = result..chunk
    end
    return result
end

local function writeFile(path, content)
    local file = io.open(path, "w")
    file:write(content)
    file:close()
end

local function exists(filename)
    return filesystem.exists(shell.getWorkingDirectory() .. "/" .. filename)
end

local function main()
    for i = 1, #paths do
        local dir = shell.getWorkingDirectory() .. "/" .. paths[i]
        if not filesystem.exists(dir) then
            filesystem.makeDirectory(dir)
        end
    end
    for i = 1, #scripts do
        local file_path = shell.getWorkingDirectory() .. "/" .. scripts[i]
        if exists(scripts[i]) then
            filesystem.remove(file_path)
        end
        local url = string.format("%s%s/%s", repo, branch, scripts[i])
        print("Downloading /"..scripts[i])
        local content = download(url)
        writeFile(file_path, content)
    end
end

if pcall(download, "http://www.msftconnecttest.com/connecttest.txt") then
    main()
else
    print("Error: Internet Disconnected")
end