-- Blitz fork: services whose price was only checked by the client's menu now check that the
-- gil was taken before they deliver. Each event is answered "pay" directly.
describe('Paid services', function()
    ---@type CClientEntityPair
    local player

    local function expectGil(amount)
        local gil = player:getGil()
        assert(gil == amount, string.format('expected %d gil, has %d', amount, gil))
    end

    describe('Voidwalker: Clear Abyssite', function()
        before_each(function()
            player = xi.test.world:spawnPlayer({ zone = xi.zone.RULUDE_GARDENS })
        end)

        it('is not given without the 1000 gil', function()
            player:setGil(999)

            player.entities:gotoAndTrigger('Assai_Nybaem', { eventId = 10120, finishOption = 1 })

            player.assert.no:hasKI(xi.keyItem.CLEAR_ABYSSITE)
            expectGil(999)
        end)

        it('is sold for 1000 gil', function()
            player:setGil(1500)

            player.entities:gotoAndTrigger('Assai_Nybaem', { eventId = 10120, finishOption = 1 })

            player.assert:hasKI(xi.keyItem.CLEAR_ABYSSITE)
            expectGil(500)
        end)
    end)

    describe('Automaton rename', function()
        local rename = 0x80000001 -- confirm bit, page 1, name 0

        before_each(function()
            player = xi.test.world:spawnPlayer({ zone = xi.zone.AHT_URHGAN_WHITEGATE, job = xi.job.PUP })
        end)

        it('does not rename without the 9800 gil', function()
            player:setGil(9799)
            local name = player:getAutomatonName()

            player.entities:gotoAndTrigger('Abda-Lurabda', { eventId = 648, finishOption = rename })

            assert(player:getAutomatonName() == name, 'the automaton should keep its name, now ' .. player:getAutomatonName())
            expectGil(9799)
        end)

        it('renames for 9800 gil', function()
            player:setGil(10000)
            local name = player:getAutomatonName()

            player.entities:gotoAndTrigger('Abda-Lurabda', { eventId = 648, finishOption = rename })

            assert(player:getAutomatonName() ~= name, 'the automaton should have a new name')
            expectGil(200)
        end)
    end)

    describe('Mog Bonanza pearl', function()
        local purchaseEvent = 912 -- Port Windurst

        before_each(function()
            -- The pearl sale only runs while the event is on.
            stub('xi.events.mogBonanza.enabledCheck', function()
                return true
            end)

            player = xi.test.world:spawnPlayer({ zone = xi.zone.PORT_WINDURST })
            player:setLocalVar('selectedNumber', 123)
        end)

        it('is not sold without the 200,000 gil', function()
            player:setGil(199999)

            xi.events.mogBonanza.onBonanzaMoogleEventFinish(player, purchaseEvent, 3, nil)

            assert(not player:hasItem(xi.item.BONANZA_PEARL), 'no pearl should be given')
            expectGil(199999)
        end)

        it('is sold for 200,000 gil', function()
            player:setGil(200000)

            xi.events.mogBonanza.onBonanzaMoogleEventFinish(player, purchaseEvent, 3, nil)

            assert(player:hasItem(xi.item.BONANZA_PEARL), 'the pearl should be given')
            expectGil(0)
        end)
    end)

    describe('Seekers of Adoulin: paying to skip The Geomagnetron', function()
        before_each(function()
            player = xi.test.world:spawnPlayer()
            player:setLevel(99)

            -- Mission conflicts, as in scripts/tests/missions/soa.lua
            player:addMission(xi.mission.log_id.ASA, xi.mission.id.asa.BURGEONING_DREAD)
            player:addMission(xi.mission.log_id.ACP, xi.mission.id.acp.A_CRYSTALLINE_PROPHECY_FIN)
            player:addMission(xi.mission.log_id.ROV, xi.mission.id.rov.A_RHAPSODY_FOR_THE_AGES)
        end)

        it('1-1 does not skip without the 1,000,000 gil', function()
            player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.RUMORS_FROM_THE_WEST)
            player:gotoZone(xi.zone.LOWER_JEUNO)
            player:setGil(999999)

            player.entities:gotoAndTrigger('Darcia', { eventId = 10117, finishOption = 2 })

            player.assert:hasMission(xi.mission.log_id.SOA, xi.mission.id.soa.RUMORS_FROM_THE_WEST)
            player.assert.no:hasKI(xi.keyItem.ADOULINIAN_CHARTER_PERMIT)
            expectGil(999999)
        end)

        it('1-2 does not skip without the 1,000,000 gil', function()
            player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.THE_GEOMAGNETRON)
            player:gotoZone(xi.zone.LOWER_JEUNO)
            player:setGil(999999)

            player.entities:gotoAndTrigger('Darcia', { eventId = 10117, finishOption = 2 })

            player.assert:hasMission(xi.mission.log_id.SOA, xi.mission.id.soa.THE_GEOMAGNETRON)
            player.assert.no:hasKI(xi.keyItem.ADOULINIAN_CHARTER_PERMIT)
            expectGil(999999)
        end)

        it('1-2 skips for 1,000,000 gil', function()
            player:addMission(xi.mission.log_id.SOA, xi.mission.id.soa.THE_GEOMAGNETRON)
            player:gotoZone(xi.zone.LOWER_JEUNO)
            player:setGil(1000000)

            player.entities:gotoAndTrigger('Darcia', { eventId = 10117, finishOption = 2 })

            player.assert:hasMission(xi.mission.log_id.SOA, xi.mission.id.soa.ONWARD_TO_ADOULIN)
            player.assert:hasKI(xi.keyItem.ADOULINIAN_CHARTER_PERMIT)
            expectGil(0)
        end)
    end)

    describe('A Moogle Kupo d\'Etat: paying Shantotto', function()
        before_each(function()
            player = xi.test.world:spawnPlayer({ zone = xi.zone.WINDURST_WALLS })
            player:addMission(xi.mission.log_id.AMK, xi.mission.id.amk.AN_ERRAND_THE_PROFESSORS_PRICE)
            player:addKeyItem(xi.keyItem.RIPE_STARFRUIT)
        end)

        it('does not take the starfruit without the 5000 gil', function()
            player:setGil(4999)

            player.entities:gotoAndTrigger('Shantotto', { eventId = 507, finishOption = 1 })

            player.assert:hasKI(xi.keyItem.RIPE_STARFRUIT)
            assert(player:getMissionStatus(xi.mission.log_id.AMK) == 0, 'the mission should not advance')
            expectGil(4999)
        end)

        it('advances for 5000 gil', function()
            player:setGil(5000)

            player.entities:gotoAndTrigger('Shantotto', { eventId = 507, finishOption = 1 })

            player.assert.no:hasKI(xi.keyItem.RIPE_STARFRUIT)
            assert(player:getMissionStatus(xi.mission.log_id.AMK) == 1, 'the mission should advance')
            expectGil(0)
        end)
    end)
end)
