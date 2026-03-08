require("globals")

local revertCode = false
local removeWhite = 0
local lastDeathPointer = 0

function ko_sora()
    if not sora_koed() then
        WriteByte(soraHP, 0)
        WriteByte(maxHP - 0x1, 0)
        WriteByte(stateFlag, 1)
        WriteShort(deathCheck, 0x9090)
        revertCode = true
    end
end

function heartless_angel_sora()
    if not sora_koed() then
        WriteByte(soraHP, 1)
        WriteByte(maxHP - 0x1, 1)
        WriteByte(soraHP + 0x8, 0)
        WriteByte(maxHP - 0x1 + 2, 0)
    end
end

function sora_koed()
    return ReadByte(maxHP - 0x1) == 0
end

function get_sora_koed()
    game_state.sora_koed = sora_koed()
end

function death_link_init()
    lastDeathPointer = ReadLong(deathPointer)
    soras_last_hp = ReadByte(soraHP)
end

function death_link_frame()
    local sora_hp_address_base = maxHP - 0x6
    local donalds_hp_address = maxHP + 0x73
    local goofys_hp_address = maxHP + 0x73 + 0x74

    if removeWhite > 0 then
        removeWhite = removeWhite - 1
        if ReadByte(white) == 128 then
            WriteByte(white, 0)
        end
    end
    -- Reverts disabling death condition check (or it crashes)
    if revertCode and ReadLong(deathPointer) ~= lastDeathPointer then
        WriteShort(deathCheck, 0x2E74)
        removeWhite = 1000
        revertCode = false
    end
    
    if goofy_death_link then
        if ReadByte(goofys_hp_address) == 0 and ReadByte(maxHP - 0x1) > 0 then
            ConsolePrint("Goofy was defeated!")
            kill_sora()
        end
    end
    if donald_death_link then
        if ReadByte(donalds_hp_address) == 0 and ReadByte(maxHP - 0x1) > 0 then
            ConsolePrint("Donald was defeated!")
            kill_sora()
        end
    end
end