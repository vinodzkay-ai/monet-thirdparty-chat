script_name("ThirdParty Room Chat")
script_author("Venmok.lua")
script_version("1.0")

local imgui = require "mimgui"
local ffi = require "ffi"
local requests = require "requests"
local cjson = require "cjson"

local new = imgui.new

-- EDIT THIS URL after deploying the Netlify backend.
local API_BASE = "https://NAMA-SITUS.netlify.app/.netlify/functions/chat"

local windowOpen = new.bool(false)
local roomInput = new.char[25]("LOBBY")
local messageInput = new.char[241]("")
local messages = {}
local roomId = "LOBBY"
local lastId = 0
local statusText = "Belum terhubung"
local nextPollAt = 0
local nextSendAt = 0
local joined = false
local MAX_MESSAGES = 40

local function trim(s)
    return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", ""))
end

local function validRoom(s)
    return #s >= 2 and #s <= 24 and s:match("^[%w_%-]+$") ~= nil
end

local function getNickname()
    if type(sampGetPlayerIdByCharHandle) == "function"
        and type(sampGetPlayerNickname) == "function"
        and type(PLAYER_PED) ~= "nil" then
        local ok, id = pcall(sampGetPlayerIdByCharHandle, PLAYER_PED)
        if ok and id ~= nil then
            local ok2, nick = pcall(sampGetPlayerNickname, id)
            if ok2 and nick and #nick > 0 then return tostring(nick):sub(1, 24) end
        end
    end
    return "Player"
end

local function apiRequest(method, url, body)
    local headers = { ["Content-Type"] = "application/json" }
    local ok, result
    if method == "GET" then
        ok, result = pcall(function()
            return requests.get(url, { headers = headers, timeout = 8 })
        end)
    else
        ok, result = pcall(function()
            return requests.post(url, {
                data = cjson.encode(body),
                headers = headers,
                timeout = 8
            })
        end)
    end
    if not ok or not result then
        return false, "HTTP error: pastikan library requests/HTTPS tersedia"
    end
    local code = tonumber(result.status_code or result.status or 0)
    local text = result.text or result.content or ""
    if code < 200 or code >= 300 then
        local msg = "HTTP " .. tostring(code)
        local parsedOk, parsed = pcall(cjson.decode, text)
        if parsedOk and parsed.error then msg = tostring(parsed.error) end
        return false, msg
    end
    local parsedOk, parsed = pcall(cjson.decode, text)
    if not parsedOk then return false, "Respons JSON tidak valid" end
    return true, parsed
end

local function joinRoom(value)
    local room = trim(value):upper()
    if not validRoom(room) then
        statusText = "Room ID: 2-24 huruf/angka/_/-"
        return
    end
    roomId = room
    lastId = 0
    messages = {}
    joined = true
    statusText = "Bergabung ke " .. roomId
    nextPollAt = 0
end

local function pollMessages()
    if not joined then return end
    local url = API_BASE .. "?room=" .. roomId .. "&after=" .. tostring(lastId)
    local ok, result = apiRequest("GET", url)
    if not ok then
        statusText = "Gagal mengambil pesan: " .. tostring(result)
        return
    end
    if type(result.messages) == "table" then
        for _, item in ipairs(result.messages) do
            local id = tonumber(item.id) or 0
            if id > lastId then lastId = id end
            messages[#messages + 1] = {
                nickname = tostring(item.nickname or "Player"):sub(1, 24),
                message = tostring(item.message or ""):sub(1, 240),
                created_at = tostring(item.created_at or "")
            }
        end
        while #messages > MAX_MESSAGES do table.remove(messages, 1) end
        statusText = "Online • Room " .. roomId
    end
end

local function sendMessage()
    if not joined then
        statusText = "Join room dahulu"
        return
    end
    local now = os.clock()
    if now < nextSendAt then
        statusText = "Tunggu sebentar sebelum mengirim lagi"
        return
    end
    local msg = trim(ffi.string(messageInput))
    if #msg < 1 then
        statusText = "Pesan tidak boleh kosong"
        return
    end
    if #msg > 240 then
        statusText = "Pesan maksimal 240 karakter"
        return
    end
    nextSendAt = now + 1.8
    local ok, result = apiRequest("POST", API_BASE, {
        action = "send",
        room = roomId,
        nickname = getNickname(),
        message = msg
    })
    if not ok then
        statusText = "Gagal kirim: " .. tostring(result)
        return
    end
    messageInput = new.char[241]("")
    statusText = "Pesan terkirim"
    pollMessages()
end

imgui.OnFrame(
    function() return windowOpen[0] end,
    function()
        imgui.SetNextWindowSize(imgui.ImVec2(520, 560), imgui.Cond.FirstUseEver)
        local visible = imgui.Begin("Third-Party Room Chat", windowOpen)
        if visible then
            imgui.TextColored(imgui.ImVec4(0.2, 0.9, 0.45, 1.0), "MONETLOADER • GLOBAL ROOM")
            imgui.TextWrapped("Status: " .. statusText)
            imgui.Separator()

            imgui.Text("Room ID")
            imgui.PushItemWidth(-105)
            imgui.InputText("##roomid", roomInput, ffi.sizeof(roomInput))
            imgui.PopItemWidth()
            imgui.SameLine()
            if imgui.Button("Join", imgui.ImVec2(90, 0)) then
                joinRoom(ffi.string(roomInput))
                pollMessages()
            end

            imgui.Separator()
            imgui.BeginChild("messages", imgui.ImVec2(0, 350), true)
            for _, item in ipairs(messages) do
                imgui.TextColored(imgui.ImVec4(0.3, 0.95, 0.5, 1.0), "[" .. item.nickname .. "]")
                imgui.SameLine()
                imgui.TextWrapped(item.message)
            end
            imgui.EndChild()

            imgui.PushItemWidth(-100)
            imgui.InputText("##message", messageInput, ffi.sizeof(messageInput))
            imgui.PopItemWidth()
            imgui.SameLine()
            if imgui.Button("Send", imgui.ImVec2(90, 0)) then sendMessage() end

            if imgui.Button("Refresh", imgui.ImVec2(100, 0)) then pollMessages() end
            imgui.SameLine()
            if imgui.Button("Close", imgui.ImVec2(100, 0)) then windowOpen[0] = false end
            imgui.End()
        end
    end
)

function main()
    while not isSampAvailable() do wait(500) end
    sampRegisterChatCommand("room", function()
        windowOpen[0] = not windowOpen[0]
        if windowOpen[0] and not joined then joinRoom(ffi.string(roomInput)) end
    end)

    while true do
        wait(250)
        if windowOpen[0] and joined and os.clock() >= nextPollAt then
            nextPollAt = os.clock() + 3.0
            pollMessages()
        end
    end
end
