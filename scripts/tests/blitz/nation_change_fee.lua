-- Blitz fork: the immigration NPCs change a player's allegiance only when the fee is taken.
-- The client is told whether the player can pay, so these answer "yes" directly.
describe('Nation change fee', function()
    local fees = { 40000, 12000, 4000 } -- by the new nation's conquest rank

    local offices =
    {
        { zone = xi.zone.METALWORKS,         npc = 'Mythily',         event = 360,   nation = xi.nation.BASTOK,   from = xi.nation.WINDURST },
        { zone = xi.zone.HEAVENS_TOWER,      npc = 'Rakano-Marukano', event = 10002, nation = xi.nation.WINDURST, from = xi.nation.SANDORIA },
        { zone = xi.zone.NORTHERN_SAN_DORIA, npc = 'Beriphaule',      event = 606,   nation = xi.nation.SANDORIA, from = xi.nation.BASTOK   },
    }

    for _, office in ipairs(offices) do
        describe(office.npc, function()
            ---@type CClientEntityPair
            local player
            local fee

            before_each(function()
                player = xi.test.world:spawnPlayer({ zone = office.zone })
                if player:isInEvent() then
                    player.events:finish()
                end

                player:setNation(office.from)

                fee = fees[GetNationRank(office.nation)]
                assert(fee, 'setup: the new nation should have a conquest rank of 1 to 3')
            end)

            it('does not change the nation of a player who cannot pay', function()
                player:setGil(fee - 1)

                player.entities:gotoAndTrigger(office.npc, { eventId = office.event, finishOption = 1 })

                assert(player:getNation() == office.from, 'the nation should be unchanged, is ' .. player:getNation())
                assert(player:getGil() == fee - 1, string.format('expected %d gil, has %d', fee - 1, player:getGil()))
            end)

            it('changes the nation of a player who pays the fee', function()
                player:setGil(fee + 500)

                player.entities:gotoAndTrigger(office.npc, { eventId = office.event, finishOption = 1 })

                assert(player:getNation() == office.nation, 'the nation should have changed, is ' .. player:getNation())
                assert(player:getGil() == 500, string.format('expected 500 gil left, has %d', player:getGil()))
            end)
        end)
    end
end)
