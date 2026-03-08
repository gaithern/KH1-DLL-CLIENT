LUAGUI_NAME = "1fmRandoClient"
LUAGUI_AUTH = "Gicu"
LUAGUI_DESC = "Kingdom Hearts 1FM Randomizer Client"

local AP              = nil -- Will load in init()
local json            = require("json")
local globals         = require("globals")
local kh1_lua_library = require("kh1_lua_library")
local send_locations  = require("client.send_locations")
local receive_items   = require("client.receive_items")
local death_link      = require("client.death_link")
local synth_hints     = require("client.synth_hints")
local ArchGUI         = require("ArchipelagoGUI")

-- AP globals
local game_name = "Kingdom Hearts"
local items_handling = 3 -- Full remote except starting inventory
local client_version = {1, 1, 0}
local message_format = nil
local ap = nil

-- Game state data
game_state = {}
game_state.victory = false
game_state.locations = {}
game_state.world = 0
game_state.sora_koed = false
game_state.hinted_locations = {}
game_state.items_received = {}
game_state.remote_location_ids = {}
game_state.slot_data = {}

frame_count = 0
location_map = {}

function copy_file(source_path, dest_path)
    local source_file, err1 = io.open(source_path, "rb") -- Open source in binary read mode
    if not source_file then
        return false, "Cannot open source file: " .. tostring(err1)
    end

    local dest_file, err2 = io.open(dest_path, "wb") -- Open destination in binary write mode
    if not dest_file then
        source_file:close()
        return false, "Cannot open destination file: " .. tostring(err2)
    end

    local chunk_size = 2^13 -- 8 KB buffer size (can be adjusted)
    while true do
        local block = source_file:read(chunk_size) -- Read in chunks
        if not block then break end -- Break loop at end of file
        local bytes_written, err3 = dest_file:write(block)
        if not bytes_written then
            source_file:close()
            dest_file:close()
            return false, "Error writing to destination file: " .. tostring(err3)
        end
    end

    source_file:close()
    dest_file:close()
    return true, "File copied successfully."
end

function copy_dll_files()
    local OTHER_PATH = SCRIPT_PATH:match("(.*)/") .. "/to_copy"
    copy_file(OTHER_PATH .. "/libgcc_s_seh-1.dll",  "libgcc_s_seh-1.dll")
    copy_file(OTHER_PATH .. "/libstdc++-6.dll",     "libstdc++-6.dll")
    copy_file(OTHER_PATH .. "/libwinpthread-1.dll", "libwinpthread-1.dll")
    copy_file(OTHER_PATH .. "/zlib1.dll",           "zlib1.dll")
end

function reset_game_state()
    game_state.items_received = {}
    game_state.slot_data = {}
end

function CheckForGUIData()
    -- This calls the C++ 'l_get_data' function via the dynamic loading we set up
    local data = ArchGUI.get_data()
    
    if data then
        ConsolePrint("C++ GUI triggered connection for: " .. tostring(data.slot))
        
        local server = data.host or ""
        local slot = data.slot or ""
        local password = data.password or ""
        
        if slot ~= "" then
            connect(server, slot, password)
        else
            ConsolePrint("GUI Error: Slot name cannot be empty!")
        end
    end
end

function connect(server, slot, password)
    function on_socket_connected()
        ConsolePrint("Socket connected")
    end

    function on_socket_error(msg)
        ConsolePrint("Socket error: " .. msg)
        show_prompt({[1]=""},{[1]={"Failed to connect...", nil}},null,142)
    end

    function on_socket_disconnected()
        ConsolePrint("Socket disconnected")
        show_prompt({[1]=""},{[1]={"Disconnected...", nil}},null,142)
        reset_game_state()
    end

    function on_room_info()
        ConsolePrint("Room info received, attempting to connect slot...")
        ap:ConnectSlot(slot, password, items_handling, {"Lua-APClientPP"}, client_version)
    end

    function on_slot_connected(slot_data)
        ConsolePrint("Slot connected successfully!")
        show_prompt({[1]=""},{[1]={"Connected!", nil}},null,142)
        reset_game_state()
        game_state.slot_data = slot_data
        if slot_data.death_link == "on" or slot_data.death_link == "toggle" then
            ap:ConnectUpdate(nil, {"Lua-APClientPP", "DeathLink"})
        else
            ap:ConnectUpdate(nil, {"Lua-APClientPP"})
        end
    end

    function on_slot_refused(reasons)
        ConsolePrint("Slot refused: " .. table.concat(reasons, ", "))
    end

    function on_items_received(items)
        for _, item in ipairs(items) do
            local item_id = item.item
            local location_id = item.location
            local sender_id = item.player
            local player_id = ap:get_player_number()
            if 2641017 <= item_id and item_id <= 2641071 then
                local acc_location_id = item_id - 2641017 + 2659100
                table.insert(game_state.locations, acc_location_id)
            end
            if player_id == sender_id and contains(game_state.slot_data.remote_location_ids, location_id) or player_id ~= sender_id then
                table.insert(game_state.items_received, item_id)
            end
        end
    end

    function on_location_info(items)
        for _, item in ipairs(items) do ConsolePrint(item.item) end
    end

    function on_location_checked(locations)
        ConsolePrint("Locations checked: " .. table.concat(locations, ", "))
    end

    function on_print(msg) ConsolePrint(msg) end

    function on_print_json(msg, extra)
        if extra.type == "ItemSend" then
            item_id = extra.item.item
            receiver_id = extra.receiving
            sender_id = extra.item.player
            location_id = extra.item.location
            local line1 = nil
            local line2 = nil
            if receiver_id == ap:get_player_number() or sender_id == ap:get_player_number() then
                item_name = ap:get_item_name(item_id, ap:get_player_game(receiver_id))
                sender_name = ap:get_player_alias(sender_id)
                receiver_name = ap:get_player_alias(receiver_id)
                if receiver_id == ap:get_player_number() and receiver_id ~= sender_id then -- Item received from someone else
                    line1 = "From " .. tostring(sender_name)
                    line2 = item_name
                elseif sender_id == ap:get_player_number() and receiver_id ~= sender_id then -- Item sent to someone else
                    line1 = item_name
                    line2 = "to " .. receiver_name
                elseif contains(game_state.slot_data.remote_location_ids, location_id) then
                    line1 = item_name
                    line2 = nil
                end
                if line1 ~= nil then
                    show_prompt({[1]=""},{[1]={line1, line2}},null,142)
                end
            end
        end
    end
    
    function on_bounced(msg)
        ConsolePrint(json.encode(msg))
        if msg.tags and contains(msg.tags, "DeathLink") and not sora_koed() then
            ko_sora()
            game_state.sora_koed = true
        end
    end

    local uuid = ""
    ap = AP(uuid, game_name, server);

    ap:set_socket_connected_handler(on_socket_connected)
    ap:set_socket_error_handler(on_socket_error)
    ap:set_socket_disconnected_handler(on_socket_disconnected)
    ap:set_room_info_handler(on_room_info)
    ap:set_slot_connected_handler(on_slot_connected)
    ap:set_slot_refused_handler(on_slot_refused)
    ap:set_items_received_handler(on_items_received)
    ap:set_location_info_handler(on_location_info)
    ap:set_location_checked_handler(on_location_checked)
    ap:set_print_handler(on_print)
    ap:set_print_json_handler(on_print_json)
    ap:set_bounced_handler(on_bounced)
end

function _OnInit()
    local initialData = ArchGUI.peek_data()
    if initialData and initialData.slot ~= "" then
        ConsolePrint("Auto-connecting to: " .. initialData.slot)
        connect(initialData.host, initialData.slot, initialData.password)
    end
    if GAME_ID == 0xAF71841E and ENGINE_TYPE == "BACKEND" then
        require("VersionCheck")
        copy_dll_files()
        AP = require("lua-apclientpp")
        message_format = AP.RenderFormat.TEXT
        location_map = fill_location_map()
    else
        ConsolePrint("KH1 not detected, not running script")
    end
end

function _OnFrame()
    if canExecute then
        local status, err = pcall(function()
            CheckForGUIData()
            handle_start_inventory()
            if get_world() ~= 0x00 and get_world() ~= 0xFF then
                frame_count = (frame_count + 1) % 60
                add_locations_to_locations_checked(frame_count)
                final_ansem_defeated()
                game_state.world = get_world()
                check_for_synth_shop_hints()
                if sora_koed() and not game_state.sora_koed and ap and (game_state.slot_data.death_link == "on" or game_state.slot_data.death_link == "toggle") then
                    ap:Bounce(
                        {
                            cause="Sora was defeated!",
                            time=os.time(),
                            source=ap:get_player_alias(ap:get_player_number())
                        }, {game_name}, {ap:get_player_number()}, {"DeathLink"})
                end
                game_state.sora_koed = sora_koed()
                death_link_frame()
                if not in_gummi_garage() then
                    receive_items_from_client(game_state.items_received)
                end
            end
            
            if ap then
                ap:LocationChecks(game_state.locations)
                ap:CreateHints(game_state.hinted_locations)
                ap:poll()
            end
        end)
        
        if not status then
            ConsolePrint("LUA ERROR: " .. tostring(err))
            canExecute = false
        end
    end
end