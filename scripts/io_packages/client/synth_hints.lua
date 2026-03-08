require("kh1_lua_library")

function synth_hints_update(hint_location_id)
    if not contains(game_state.hinted_locations, hint_location_id) then
        table.insert(game_state.hinted_locations, hint_location_id)
    end
end

function update_synth_hints_table()
    synth_level_offset = 0xCC3
    synth_level = ReadByte(worldFlagBase - 0x1443 + synth_level_offset)
    local i = 1
    while i <= 6 * (math.min(synth_level, 4) + 1) do
        synth_hints_update(2656400 + i)
        i = i + 1
    end
    if synth_level == 5 then
        synth_hints_update(game_state.hinted_locations, 2656431)
        synth_hints_update(game_state.hinted_locations, 2656432)
        synth_hints_update(game_state.hinted_locations, 2656433)
    end
end

function check_for_synth_shop_hints()
    local spawn = worldMapLines + 0x136
    if ReadByte(world) == 0x03 and ReadByte(room) == 0x0B and (ReadByte(spawn) == 0x36 or ReadByte(spawn) == 0x34) then
        update_synth_hints_table()
    end
end