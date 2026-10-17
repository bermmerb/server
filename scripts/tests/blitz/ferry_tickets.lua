-- Blitz fork: ferry ticket sellers hand over the ticket only when the 100 gil is taken.
-- Each seller's event is answered "yes" directly, as a client that skips the price check would.
describe('Ferry ticket sellers', function()
    local sellers =
    {
        { zone = xi.zone.MHAURA,               npc = 'Felisa',  event = 221, option = 333, ticket = xi.keyItem.FERRY_TICKET            },
        { zone = xi.zone.AHT_URHGAN_WHITEGATE, npc = 'Tazhaal', event = 221, option = 333, ticket = xi.keyItem.FERRY_TICKET            },
        { zone = xi.zone.AHT_URHGAN_WHITEGATE, npc = 'Atiza',   event = 223, option = 333, ticket = xi.keyItem.SILVER_SEA_FERRY_TICKET },
        { zone = xi.zone.NASHMAU,              npc = 'Abihaal', event = 221, option = 333, ticket = xi.keyItem.SILVER_SEA_FERRY_TICKET },

        -- Lucia sells from outside the dock gate (z >= -28.75) and the sale counts once the player
        -- is past it (option is always 0).
        { zone = xi.zone.SELBINA, npc = 'Lucia', event = 221, option = 0, ticket = xi.keyItem.FERRY_TICKET, from = -27.5, through = -30.5 },
    }

    local function buy(player, seller)
        if seller.from then
            local npc = player.entities:get(seller.npc)
            player:setPos(npc:getXPos(), npc:getYPos(), seller.from)
            player.actions:trigger(npc)
            player:setPos(npc:getXPos(), npc:getYPos(), seller.through)
        else
            player.entities:gotoAndTrigger(seller.npc)
        end

        player.events:finish(seller.event, seller.option)
    end

    for _, seller in ipairs(sellers) do
        describe(seller.npc, function()
            ---@type CClientEntityPair
            local player

            before_each(function()
                player = xi.test.world:spawnPlayer({ zone = seller.zone })
            end)

            it('does not give the ticket without the 100 gil', function()
                player:setGil(99)

                buy(player, seller)

                player.assert.no:hasKI(seller.ticket)
                assert(player:getGil() == 99, 'gil should be unchanged, has ' .. player:getGil())
            end)

            it('gives the ticket for 100 gil', function()
                player:setGil(150)

                buy(player, seller)

                player.assert:hasKI(seller.ticket)
                assert(player:getGil() == 50, 'expected 50 gil left, has ' .. player:getGil())
            end)
        end)
    end
end)
