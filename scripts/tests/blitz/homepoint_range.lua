-- Blitz fork: setHomePoint stores where the player stands, so a home point is only set within
-- talk range of the NPC whose menu sets it. The stock client cannot walk while a menu is open,
-- so the negative cases send the position updates raw, as a packet tool would.

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

describe('Home point set', function()
    ---@type CClientEntityPair
    local player
    local start

    before_each(function()
        player = xi.test.world:spawnPlayer({ zone = xi.zone.SOUTHERN_SAN_DORIA })
        if player:isInEvent() then
            player.events:finish()
        end

        player:setNation(xi.nation.SANDORIA)
        player:setHomePoint()
        start = here(player)
    end)

    -- Where the home point is: warp to it from another zone.
    local function expectHomePointAt(pos, what)
        player:setPos(0, 0, 0, 0, xi.zone.NORTHERN_SAN_DORIA)
        settle()
        player:warp()
        settle()

        player.assert:inZone(xi.zone.SOUTHERN_SAN_DORIA)
        expectAt(player, pos, what)
    end

    local function standAway(npc, yalms)
        local pos = { x = npc:getXPos() + yalms, y = npc:getYPos(), z = npc:getZPos() }
        player.actions:move(pos.x, pos.y, pos.z)
        expectAt(player, pos, 'setup: the player\'s step')
    end

    local function openMenu(npc)
        player.actions:trigger(npc)
        assert(player:isInEvent(), 'setup: the menu should be open')
    end

    -- Each NPC: its event and the menu answer that sets the home point.
    local setters =
    {
        { name = 'HomePoint#1', event = 8700,  set = 1 }, -- Home Point crystal, SET_HOMEPOINT
        { name = 'Arpevion_TK', event = 32763, set = 4 }, -- San d'Oria city guard, Homepoint -> Set
    }

    for _, setter in ipairs(setters) do
        describe(setter.name, function()
            local npc

            before_each(function()
                npc = player.entities:get(setter.name)
                assert(player:checkDistance(npc) > 20, 'setup: the player should start away from ' .. setter.name)
            end)

            -- The menu stays open while raw position updates take the player out of talk range (6 yalms).
            for _, yalms in ipairs({ 7, 20 }) do
                it(string.format('is not set %d yalms off, where the player walked to with the menu open', yalms), function()
                    player.entities:moveTo(npc)
                    openMenu(npc)

                    standAway(npc, yalms)
                    player.events:finish(setter.event, setter.set)

                    expectHomePointAt(start, 'the home point should not have moved')
                end)
            end

            it('is set where the player stands at the NPC', function()
                player.entities:moveTo(npc)
                local spot = here(player)
                openMenu(npc)

                player.events:finish(setter.event, setter.set)

                expectHomePointAt(spot, 'the home point should be where the player talked to the NPC')
            end)

            it('is set at the edge of the NPC\'s talk range', function()
                standAway(npc, 5.5)
                local spot = here(player)
                openMenu(npc)

                player.events:finish(setter.event, setter.set)

                expectHomePointAt(spot, 'the home point should be where the player talked to the NPC')
            end)
        end)
    end
end)
