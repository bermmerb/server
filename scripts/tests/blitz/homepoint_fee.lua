-- Blitz fork: the Home Point teleport fee is charged before the warp, and an unaffordable
-- teleport does not happen. Only the client's menu greys the choice out, so these send the
-- menu answers directly.
describe('Home Point teleport fee', function()
    ---@type CClientEntityPair
    local player

    local event         = 8700 -- Southern San d'Oria HomePoint#1 (index 0, group 1)
    local bastokMarkets = 11   -- Bastok Markets #1 (group 2, fee 1): 500 gil from San d'Oria
    local teleport      = 2 + bastokMarkets * 65536 -- TELEPORT | index << 16

    local function expectGil(amount)
        local gil = player:getGil()
        assert(gil == amount, string.format('expected %d gil, has %d', amount, gil))
    end

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.SOUTHERN_SAN_DORIA })
        player:addTeleport(xi.teleport.type.HOMEPOINT, bastokMarkets % 32, math.floor(bastokMarkets / 32))
    end)

    it('does not warp a player who cannot pay', function()
        player:setGil(0)

        player.entities:gotoAndTrigger('HomePoint#1')
        player.events:expect({ eventId = event, updates = { teleport }, finishOption = teleport })

        player.assert:inZone(xi.zone.SOUTHERN_SAN_DORIA)
        assert(not player:isPendingZone(), 'the player should not be zoning')
        expectGil(0)
    end)

    it('charges the fee and warps a player who can pay', function()
        player:setGil(1000)

        player.entities:gotoAndTrigger('HomePoint#1')
        player.events:expect({ eventId = event, updates = { teleport }, finishOption = teleport })

        player.assert:inZone(xi.zone.BASTOK_MARKETS)
        expectGil(500)
    end)
end)
