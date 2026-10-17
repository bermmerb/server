-- Blitz fork: the airship fare is a condition of boarding. A departure gate takes the 200 gil
-- when its cutscene walks the player through; a player who reached the deck without paying
-- there pays when the airship collects them, or is left ashore.
-- xi_test runs no ships, so these stand the player in the boarding area and call the zone's
-- onTransportEvent the way CZoneEntities::TransportDepart does.
describe('Airship fare', function()
    local fare = 200

    -- One entry per berth: where its boarding area is, and the events onTransportEvent starts.
    local berths =
    {
        windurst =
        {
            zone = xi.zone.PORT_WINDURST, area = 416, deck = { 249.47, -3.9, 69.17 },
            airship = xi.zone.WINDURST_JEUNO_AIRSHIP, board = 10002, ashore = 10003,
        },
        sandoria =
        {
            zone = xi.zone.PORT_SAN_DORIA, area = 369, deck = { 20.0, -2.4, 54.15 },
            airship = xi.zone.SAN_DORIA_JEUNO_AIRSHIP, board = 700, ashore = 701,
        },
        bastok =
        {
            zone = xi.zone.PORT_BASTOK, area = 315, deck = { -26.3, 6.0, -77.3 },
            airship = xi.zone.BASTOK_JEUNO_AIRSHIP, board = 71, ashore = 72,
        },
        kazham =
        {
            zone = xi.zone.KAZHAM, area = 512, deck = { 6.15, -3.9, 32.15 },
            airship = xi.zone.KAZHAM_JEUNO_AIRSHIP, board = 10000, ashore = 10001, pass = xi.keyItem.AIRSHIP_PASS_FOR_KAZHAM,
        },
        jeunoSandoria =
        {
            zone = xi.zone.PORT_JEUNO, area = 474, deck = { -68.0, 10.0, 127.15 },
            airship = xi.zone.SAN_DORIA_JEUNO_AIRSHIP, board = 10010, ashore = 10014,
        },
        jeunoBastok =
        {
            zone = xi.zone.PORT_JEUNO, area = 475, deck = { -70.0, 10.0, -127.15 },
            airship = xi.zone.BASTOK_JEUNO_AIRSHIP, board = 10012, ashore = 10016,
        },
        jeunoWindurst =
        {
            zone = xi.zone.PORT_JEUNO, area = 476, deck = { -6.0, 10.0, -127.15 },
            airship = xi.zone.WINDURST_JEUNO_AIRSHIP, board = 10011, ashore = 10015,
        },
        jeunoKazham =
        {
            zone = xi.zone.PORT_JEUNO, area = 477, deck = { -4.0, 10.0, 127.15 },
            airship = xi.zone.KAZHAM_JEUNO_AIRSHIP, board = 10013, ashore = 10017, pass = xi.keyItem.AIRSHIP_PASS_FOR_KAZHAM,
        },
    }

    local berthOrder = { 'windurst', 'sandoria', 'bastok', 'kazham', 'jeunoSandoria', 'jeunoBastok', 'jeunoWindurst', 'jeunoKazham' }

    -- Every departure gate (the door and the attendants beside it), the event it opens and a spot
    -- past it, where the gate's cutscene leaves a player who goes through. Varden only serves a
    -- player who talks to him from outside the gate.
    local gates =
    {
        { berth = 'windurst',      npc = '_6o6',             event = 181, through = { x = 223.5 } },
        { berth = 'windurst',      npc = 'Honorio',          event = 181, through = { x = 223.5 } },
        { berth = 'sandoria',      npc = '_6g9',             event = 604, through = { x = -10.5 } },
        { berth = 'sandoria',      npc = 'Anton',            event = 604, through = { x = -10.5 } },
        { berth = 'bastok',        npc = '_6k8',             event = 141, through = { x = -56.5 } },
        { berth = 'bastok',        npc = 'Rajesh',           event = 141, through = { x = -56.5 } },
        { berth = 'bastok',        npc = 'Varden',           event = 141, through = { x = -56.5 }, from = { x = -59.5 } },
        { berth = 'kazham',        npc = 'Bhoyu_Halpatacco', event = 116, through = { z = -8.0 } },
        { berth = 'jeunoSandoria', npc = '_6u4',             event = 38,  through = { z = 59.5 } },
        { berth = 'jeunoSandoria', npc = 'Purequane',        event = 38,  through = { z = 59.5 } },
        { berth = 'jeunoKazham',   npc = '_6u8',             event = 37,  through = { z = 59.5 } },
        { berth = 'jeunoKazham',   npc = 'Illauvolahaut',    event = 37,  through = { z = 59.5 } },
        { berth = 'jeunoBastok',   npc = '_6ua',             event = 36,  through = { z = -59.5 } },
        { berth = 'jeunoBastok',   npc = 'Zedduva',          event = 36,  through = { z = -59.5 } },
        { berth = 'jeunoWindurst', npc = '_6ue',             event = 39,  through = { z = -59.5 } },
        { berth = 'jeunoWindurst', npc = 'Omiro-Zamiro',     event = 39,  through = { z = -59.5 } },
    }

    local function zoneScript(zoneId)
        return xi.zones[GetZone(zoneId):getName()].Zone
    end

    local function passenger(berth, gil)
        local player = xi.test.world:spawnPlayer({ zone = berth.zone })
        player:addKeyItem(berth.pass or xi.keyItem.AIRSHIP_PASS)
        player:setGil(gil)

        return player
    end

    local function expectGil(player, amount)
        local gil = player:getGil()
        assert(gil == amount, string.format('expected %d gil, has %d', amount, gil))
    end

    local function goThroughGate(player, gate, through)
        if gate.from then
            local npc = player.entities:get(gate.npc)
            player:setPos(gate.from.x, npc:getYPos(), npc:getZPos())
            player.actions:trigger(npc)
        else
            player.entities:gotoAndTrigger(gate.npc)
        end

        if through then
            player:setPos(gate.through.x or player:getXPos(), player:getYPos(), gate.through.z or player:getZPos())
        end

        player.events:finish(gate.event, 0)
    end

    -- Stand in the boarding area as the airship leaves, so the zone decides about the player.
    local function departure(player, berth)
        player:setPos(berth.deck[1], berth.deck[2], berth.deck[3])
        xi.test.world:tick(xi.tick.TRIGGER_AREAS)
        assert(player:isPlayerInTriggerArea(berth.area), string.format('the player should be in boarding area %d', berth.area))

        zoneScript(berth.zone).onTransportEvent(player, berth.airship, '')
    end

    local function expectBoarded(player, berth)
        player.events:expect({ eventId = berth.board })
        player.assert:inZone(berth.airship)
    end

    local function expectLeftAshore(player, berth)
        player.events:expect({ eventId = berth.ashore })
        player.assert:inZone(berth.zone)
    end

    for _, name in ipairs(berthOrder) do
        local berth = berths[name]

        describe(name .. ' berth', function()
            it('leaves a player who reached the deck without paying, and cannot pay, ashore', function()
                local player = passenger(berth, fare - 1)

                departure(player, berth)

                expectLeftAshore(player, berth)
                expectGil(player, fare - 1)
            end)

            it('takes the fare at boarding from a player who reached the deck without paying', function()
                local player = passenger(berth, 1000)

                departure(player, berth)

                expectBoarded(player, berth)
                expectGil(player, 1000 - fare)
            end)
        end)
    end

    for _, gate in ipairs(gates) do
        local berth = berths[gate.berth]

        it(string.format('%s takes the fare once for the airship it leads to', gate.npc), function()
            local player = passenger(berth, 1000)

            goThroughGate(player, gate, true)
            expectGil(player, 1000 - fare)

            departure(player, berth)

            expectBoarded(player, berth)
            expectGil(player, 1000 - fare)
        end)
    end

    it('charges at boarding a player whose gate cutscene did not take the fare', function()
        local berth  = berths.windurst
        local player = passenger(berth, 1000)

        goThroughGate(player, gates[1], false)
        expectGil(player, 1000)

        departure(player, berth)

        expectBoarded(player, berth)
        expectGil(player, 1000 - fare)
    end)

    it('boards a player who has exactly the fare left at boarding', function()
        local berth  = berths.windurst
        local player = passenger(berth, fare)

        departure(player, berth)

        expectBoarded(player, berth)
        expectGil(player, 0)
    end)

    it('takes a paid fare for one trip only', function()
        local berth  = berths.windurst
        local player = passenger(berth, 1000)

        goThroughGate(player, gates[1], true)
        departure(player, berth)
        expectBoarded(player, berth)

        -- Back on the dock where the airship lands (outside the boarding area), with no gil.
        player:gotoZone(berth.zone, { x = 228, y = -3, z = 76 })
        player:setGil(0)

        departure(player, berth)

        expectLeftAshore(player, berth)
    end)
end)
