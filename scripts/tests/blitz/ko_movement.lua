-- Blitz fork: a KO'd character lies where it fell until it is raised or returns to its home point.
-- The stock client cannot walk while KO'd, so the negative cases send the position update and the
-- zone line request raw, as a packet tool would.
local ffi = require('ffi')

local function settle()
    for _ = 1, 8 do
        xi.test.world:skipTime(1)
    end
end

local function here(player)
    return { x = player:getXPos(), y = player:getYPos(), z = player:getZPos(), rot = player:getRotPos() }
end

local function expectAt(player, pos, what)
    local d = player:checkDistance(pos.x, pos.y, pos.z)
    assert(d < 0.01, string.format('%s: the player should be at (%.2f, %.2f, %.2f), is %.2f yalms away', what, pos.x, pos.y, pos.z, d))
end

local function expectFacing(player, rot, what)
    assert(player:getRotPos() == rot, string.format('%s: the player should face %d, faces %d', what, rot, player:getRotPos()))
end

describe('KO movement and zone lines', function()
    ---@type CClientEntityPair
    local player

    -- West Ronfaure's zone line into Southern San d'Oria (data/zones/west_ronfaure/zone.yaml, z2s0).
    local zoneLine = { id = 'z2s0', x = -119.065, y = -65.707, z = 280.921 }

    -- 0x05E: the zone line's fourcc at 0x04, the rest unused or 0.
    local function requestZoneLine()
        local packet = ffi.new('uint8_t[24]')
        ffi.copy(packet + 4, zoneLine.id, 4)
        player.packets:send(0x05E, packet, ffi.sizeof(packet))
        settle()
    end

    -- 0x01A: the KO menu's return to the home point (ActionID HomepointMenu 0x0B, StatusId Accept 0).
    local function returnToHomePoint()
        local packet = ffi.new('uint8_t[28]')
        ffi.cast('uint32_t*', packet + 4)[0]  = player:getID()
        ffi.cast('uint16_t*', packet + 8)[0]  = player:getTargID()
        ffi.cast('uint16_t*', packet + 10)[0] = 0x0B
        player.packets:send(0x01A, packet, ffi.sizeof(packet))
        settle()
    end

    local function knockOut()
        player:setHP(0)
        xi.test.world:tickEntity(player)
        assert(player:isDead(), 'setup: the player should be KO\'d')
    end

    before_each(function()
        -- Home point in Southern San d'Oria, then out to West Ronfaure, 3 yalms from the zone line.
        player = xi.test.world:spawnPlayer({ zone = xi.zone.SOUTHERN_SAN_DORIA })
        player:setHomePoint()

        player:setPos(zoneLine.x + 3, zoneLine.y, zoneLine.z, 0, xi.zone.WEST_RONFAURE)
        settle()
        player.assert:inZone(xi.zone.WEST_RONFAURE)
    end)

    it('moves and turns an alive player with its position updates', function()
        player.actions:move(zoneLine.x + 6, zoneLine.y, zoneLine.z + 4, 64)

        expectAt(player, { x = zoneLine.x + 6, y = zoneLine.y, z = zoneLine.z + 4 }, 'after the step')
        expectFacing(player, 64, 'after the step')
    end)

    it('does not move or turn a KO\'d player', function()
        player.actions:move(zoneLine.x + 6, zoneLine.y, zoneLine.z + 4, 64)
        expectAt(player, { x = zoneLine.x + 6, y = zoneLine.y, z = zoneLine.z + 4 }, 'setup: the step while alive')
        knockOut()
        local fell = here(player)

        player.actions:move(fell.x + 20, fell.y, fell.z + 20, 192)

        expectAt(player, fell, 'the corpse')
        expectFacing(player, fell.rot, 'the corpse')
        assert(player:isDead(), 'the player should still be KO\'d')
    end)

    it('moves a raised player again', function()
        knockOut()
        player:sendRaise(1)
        player.actions:acceptRaise()
        settle()
        assert(player:isAlive(), 'setup: the player should be raised')

        local raised = here(player)
        player.actions:move(raised.x + 5, raised.y, raised.z, 32)

        expectAt(player, { x = raised.x + 5, y = raised.y, z = raised.z }, 'after the step')
        expectFacing(player, 32, 'after the step')
    end)

    it('takes an alive player through the zone line', function()
        requestZoneLine()

        player.assert:inZone(xi.zone.SOUTHERN_SAN_DORIA)
    end)

    it('does not take a KO\'d player through the zone line', function()
        knockOut()
        local fell = here(player)

        requestZoneLine()

        player.assert:inZone(xi.zone.WEST_RONFAURE)
        assert(not player:isPendingZone(), 'the player should not be zoning')
        assert(player:isDead(), 'the player should still be KO\'d')
        expectAt(player, fell, 'the corpse')
        expectFacing(player, fell.rot, 'the corpse')
    end)

    it('still returns a KO\'d player to its home point from the KO menu', function()
        knockOut()

        returnToHomePoint()

        player.assert:inZone(xi.zone.SOUTHERN_SAN_DORIA)
        assert(player:isAlive(), 'the player should be revived at the home point')
    end)
end)
