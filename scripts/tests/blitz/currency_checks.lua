-- Blitz fork: delCurrency and delSeals stop at 0 and return nothing, so a service that
-- delivers first and then deducts is free for a player who cannot pay. These services now
-- check the balance first. Each event is answered "pay" directly, as a raw packet would.
describe('Currency checks', function()
    ---@type CClientEntityPair
    local player

    local function spawn(zone)
        player = xi.test.world:spawnPlayer({ zone = zone })
        if player:isInEvent() then
            player.events:finish()
        end
    end

    local function expectCurrency(currency, amount)
        local held = player:getCurrency(currency)
        assert(held == amount, string.format('expected %d %s, has %d', amount, currency, held))
    end

    describe('Veridical Conflux activation', function()
        local function isActive()
            -- Abyssea - Konschtat is offset 0, Veridical Conflux #01 is bit 0.
            return utils.mask.getBit(player:getTeleport(xi.teleport.type.ABYSSEA_CONFLUX, 0), 0)
        end

        local function activate()
            player.entities:gotoAndTrigger('Veridical_Conflux_#01', { eventId = 2132, finishOption = 1 })
        end

        before_each(function()
            spawn(xi.zone.ABYSSEA_KONSCHTAT)
            assert(not isActive(), 'setup: the conflux should not be active')
        end)

        it('does not activate without the 50 cruor', function()
            player:setCurrency('cruor', 49)

            activate()

            assert(not isActive(), 'the conflux should not be active')
            expectCurrency('cruor', 49)
        end)

        it('activates for 50 cruor', function()
            player:setCurrency('cruor', 50)

            activate()

            assert(isActive(), 'the conflux should be active')
            expectCurrency('cruor', 0)
        end)

        it('activates for the discounted price the client is shown', function()
            -- Two Abyssites of Confluence: 0.6 * 50, which is 30.000000000000004 in floating point.
            player:addKeyItem(xi.keyItem.IVORY_ABYSSITE_OF_CONFLUENCE)
            player:addKeyItem(xi.keyItem.CRIMSON_ABYSSITE_OF_CONFLUENCE)
            player:setCurrency('cruor', 30)

            activate()

            assert(isActive(), 'the conflux should be active')
            expectCurrency('cruor', 0)
        end)
    end)

    describe('Allied Sigil', function()
        local twoExtraEffects = bit.bor(bit.lshift(6, 11), 1) -- Latent Regen and Latent Refresh

        local function buySigil(option)
            player.entities:gotoAndTrigger('Miliart_TK', { eventId = 110, finishOption = option })
        end

        before_each(function()
            spawn(xi.zone.SOUTHERN_SAN_DORIA_S)
            player:setCampaignAllegiance(1)
            player:addKeyItem(xi.keyItem.BRONZE_RIBBON_OF_SERVICE)
        end)

        it('is not given with extra effects the player cannot pay for', function()
            player:setCurrency('allied_notes', 99)

            buySigil(twoExtraEffects)

            assert(not player:hasStatusEffect(xi.effect.SIGIL), 'no Sigil should be given')
            expectCurrency('allied_notes', 99)
        end)

        it('adds two extra effects for 100 notes', function()
            player:setCurrency('allied_notes', 100)

            buySigil(twoExtraEffects)

            assert(player:hasStatusEffect(xi.effect.SIGIL), 'the Sigil should be given')
            expectCurrency('allied_notes', 0)
        end)

        it('is free without extra effects', function()
            player:setCurrency('allied_notes', 0)

            buySigil(1)

            assert(player:hasStatusEffect(xi.effect.SIGIL), 'the Sigil should be given')
            expectCurrency('allied_notes', 0)
        end)
    end)

    describe('Assault Armband', function()
        local staging =
        {
            { zone = xi.zone.MOUNT_ZHAYOLM,    npc = 'Waudeen', event = 209, orders = xi.keyItem.LEBROS_ASSAULT_ORDERS    },
            { zone = xi.zone.BHAFLAU_THICKETS, npc = 'Daswil',  event = 512, orders = xi.keyItem.MAMOOL_JA_ASSAULT_ORDERS },
            { zone = xi.zone.CAEDARVA_MIRE,    npc = 'Nahshib', event = 148, orders = xi.keyItem.PERIQIA_ASSAULT_ORDERS   },
            { zone = xi.zone.CAEDARVA_MIRE,    npc = 'Nareema', event = 149, orders = xi.keyItem.LEUJAOAM_ASSAULT_ORDERS  },
            { zone = xi.zone.ARRAPAGO_REEF,    npc = 'Meyaada', event = 223, orders = xi.keyItem.ILRUSI_ASSAULT_ORDERS    },
        }

        for _, point in ipairs(staging) do
            describe(point.npc, function()
                before_each(function()
                    spawn(point.zone)
                    player:addMission(xi.mission.log_id.TOAU, xi.mission.id.toau.PRESIDENT_SALAHEEM)
                    player:addKeyItem(point.orders)
                end)

                it('is not given without the 50 Imperial Standing', function()
                    player:setCurrency('imperial_standing', 49)

                    player.entities:gotoAndTrigger(point.npc, { eventId = point.event, finishOption = 1 })

                    player.assert.no:hasKI(xi.keyItem.ASSAULT_ARMBAND)
                    expectCurrency('imperial_standing', 49)
                end)

                it('is given for 50 Imperial Standing', function()
                    player:setCurrency('imperial_standing', 50)

                    player.entities:gotoAndTrigger(point.npc, { eventId = point.event, finishOption = 1 })

                    player.assert:hasKI(xi.keyItem.ASSAULT_ARMBAND)
                    expectCurrency('imperial_standing', 0)
                end)
            end)
        end
    end)

    describe('Nyzul Isle vending box: preferred items', function()
        local vendingBoxEvent = 202
        local givePreferred   = 4353
        local barbarians      = xi.item.BOTTLE_OF_BARBARIANS_DRINK -- preference bit 1, 100 tokens
        local fighters        = xi.item.BOTTLE_OF_FIGHTERS_DRINK   -- preference bit 2, 100 tokens

        local function hasTempItem(itemId)
            return player:hasItem(itemId, xi.inventoryLocation.TEMPITEMS)
        end

        before_each(function()
            -- The box sits in the Nyzul Isle instance; its handler only needs the player.
            spawn()
        end)

        it('is not given without the tokens', function()
            player:setCharVar('[Nyzul]preferredItems', utils.mask.setBit(0, 1, true))
            player:setCurrency('nyzul_isle_assault_point', 99)

            xi.nyzul.vendingBoxOnEventUpdate(player, vendingBoxEvent, givePreferred)

            assert(not hasTempItem(barbarians), 'no temporary item should be given')
            expectCurrency('nyzul_isle_assault_point', 99)
        end)

        it('is given for its price', function()
            player:setCharVar('[Nyzul]preferredItems', utils.mask.setBit(0, 1, true))
            player:setCurrency('nyzul_isle_assault_point', 100)

            xi.nyzul.vendingBoxOnEventUpdate(player, vendingBoxEvent, givePreferred)

            assert(hasTempItem(barbarians), 'the temporary item should be given')
            expectCurrency('nyzul_isle_assault_point', 0)
        end)

        it('charges for every item it gives', function()
            player:setCharVar('[Nyzul]preferredItems', utils.mask.setBit(utils.mask.setBit(0, 1, true), 2, true))
            player:setCurrency('nyzul_isle_assault_point', 150)

            xi.nyzul.vendingBoxOnEventUpdate(player, vendingBoxEvent, givePreferred)

            local given = (hasTempItem(barbarians) and 1 or 0) + (hasTempItem(fighters) and 1 or 0)
            local spent = 150 - player:getCurrency('nyzul_isle_assault_point')
            assert(spent == given * 100, string.format('%d items given for %d tokens', given, spent))
        end)
    end)

    describe('Shemo seal exchange', function()
        local beastmenSeal  = 0
        local kindredSeal   = 1
        local oneForThree   = bit.bor(bit.lshift(1, 8), bit.lshift(beastmenSeal + 1, 4), kindredSeal + 1)

        local function expectSeals(sealType, amount)
            local held = player:getSeals(sealType)
            assert(held == amount, string.format('expected %d seals of type %d, has %d', amount, sealType, held))
        end

        before_each(function()
            spawn(xi.zone.PORT_JEUNO)
            assert(player:getSeals(beastmenSeal) == 0 and player:getSeals(kindredSeal) == 0, 'setup: no stored seals')
        end)

        it('does not exchange seals the player has not stored', function()
            player:addSeals(2, beastmenSeal)

            player.entities:gotoAndTrigger('Shemo', { eventId = 352, finishOption = oneForThree })

            expectSeals(kindredSeal, 0)
            expectSeals(beastmenSeal, 2)
        end)

        it('exchanges three seals for one', function()
            player:addSeals(3, beastmenSeal)

            player.entities:gotoAndTrigger('Shemo', { eventId = 352, finishOption = oneForThree })

            expectSeals(kindredSeal, 1)
            expectSeals(beastmenSeal, 0)
        end)
    end)
end)
