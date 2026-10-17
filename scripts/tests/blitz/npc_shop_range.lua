-- Blitz fork: buying (0x083), appraising (0x084) and selling (0x085) need a shop opened by an NPC in the
-- player's zone, and the player still near that NPC. Before, the last shop stayed usable from anywhere
-- in the zone, and a sale worked with no shop open at all, at the full base price. A shop window only
-- opens by talking to its NPC, and the client closes it when the player walks away; the negative cases
-- send the packets raw, as a packet tool would.
local ffi = require('ffi')

local feather = xi.item.CHOCOBO_FEATHER

local function u16(d, o)
    return d[o] + d[o + 1] * 256
end

local function u32(d, o)
    return d[o] + d[o + 1] * 256 + d[o + 2] * 65536 + d[o + 3] * 16777216
end

local function incoming(player, packetType)
    local out = {}
    for _, packet in ipairs(player.packets:getIncoming()) do
        if packet.type == packetType then
            table.insert(out, packet)
        end
    end

    return out
end

-- The rows of the shop list the server sent (0x03C): { [itemId] = { index, price } }.
local function shopRows(player)
    local rows = {}
    for _, packet in ipairs(incoming(player, 0x03C)) do
        for row = 0, math.floor((packet.size - 0x08) / 12) - 1 do
            local o = 0x08 + row * 12
            rows[u16(packet.data, o + 4)] = { index = packet.data[o + 6], price = u32(packet.data, o) }
        end
    end

    return rows
end

-- Talk to the NPC from where the player stands and expect its shop (0x03E then 0x03C).
local function openShop(player, npc)
    player.packets:clear()
    player.actions:trigger(npc)
    assert(#incoming(player, 0x03E) == 1, 'setup: talking to ' .. npc:getName() .. ' should open the shop')
    return shopRows(player)
end

local function cheapestRow(rows)
    local best = nil
    for itemId, row in pairs(rows) do
        if not best or row.price < best.price then
            best = { itemId = itemId, index = row.index, price = row.price }
        end
    end

    assert(best, 'setup: the shop should list something')
    return best
end

local function buy(player, index, quantity)
    xi.test.world:skipTime(1) -- 0x083 is rate limited (settings/default/network.lua)
    player.actions:shopBuy(index, quantity)
end

-- 0x084 appraisal of the item in a bag slot; returns the quoted unit price (0x03D), or nil.
local function appraise(player, itemId, quantity)
    local item = player:findItem(itemId, xi.inv.INVENTORY)
    assert(item, 'setup: the item to sell should be in the bag')

    local packet = ffi.new('uint8_t[12]')
    packet[4]    = quantity
    packet[8]    = itemId % 256
    packet[9]    = math.floor(itemId / 256)
    packet[10]   = item:getSlotID()

    player.packets:clear()
    player.packets:send(0x084, packet, assert(ffi.sizeof(packet)))
    local quotes = incoming(player, 0x03D)
    return quotes[1] and u32(quotes[1].data, 4) or nil
end

-- 0x085 confirms the sale of the last appraisal.
local function confirmSale(player)
    local packet = ffi.new('uint8_t[8]')
    packet[4]    = 1 -- SellFlag
    player.packets:send(0x085, packet, assert(ffi.sizeof(packet)))
end

local function stepAway(player, npc, yalms)
    player.actions:move(npc:getXPos() + yalms, npc:getYPos(), npc:getZPos())
    local d = player:checkDistance(npc)
    assert(math.abs(d - yalms) < 0.1, string.format('setup: the player should be %d yalms from %s, is %.1f', yalms, npc:getName(), d))
end

local function expectUnchanged(player, gil, feathers, what)
    assert(player:getGil() == gil, string.format('%s: gil should stay %d, is %d', what, gil, player:getGil()))
    assert(player:getItemCount(feather) == feathers, string.format('%s: feathers should stay %d, are %d', what, feathers, player:getItemCount(feather)))
end

describe('NPC shop range', function()
    ---@type CClientEntityPair
    local player

    local function spawnIn(zoneId)
        player = xi.test.world:spawnPlayer({ zone = zoneId })
        if player:isInEvent() then
            player.events:finish()
        end

        player:setGil(10000)
    end

    describe('Ferdoulemiont (Southern San d\'Oria)', function()
        local merchant

        -- Talk to the merchant standing on his spot, as gotoAndTrigger does.
        local function atShop()
            player.entities:moveTo(merchant)
            local rows = openShop(player, merchant)
            assert(rows[feather], 'setup: Ferdoulemiont should sell Chocobo Feathers')
            return rows[feather]
        end

        before_each(function()
            spawnIn(xi.zone.SOUTHERN_SAN_DORIA)
            merchant = player.entities:get('Ferdoulemiont')
            assert(player:checkDistance(merchant) > 20, 'setup: the player should start away from the merchant')
        end)

        it('refuses a sale with no shop open', function()
            player:addItem(feather)

            local quote = appraise(player, feather, 1)
            confirmSale(player)

            assert(quote == nil, 'there should be no quote, got ' .. tostring(quote))
            expectUnchanged(player, 10000, 1, 'a sale with no shop open')
        end)

        for _, yalms in ipairs({ 25, 40 }) do
            it(string.format('refuses a purchase through a shop opened earlier, %d yalms from the merchant', yalms), function()
                local row = atShop()

                stepAway(player, merchant, yalms)
                buy(player, row.index, 1)

                expectUnchanged(player, 10000, 0, 'a far purchase')
            end)

            it(string.format('refuses a sale through a shop opened earlier, %d yalms from the merchant', yalms), function()
                player:addItem(feather)
                atShop()

                stepAway(player, merchant, yalms)
                local quote = appraise(player, feather, 1)
                confirmSale(player)

                assert(quote == nil, 'there should be no quote, got ' .. tostring(quote))
                expectUnchanged(player, 10000, 1, 'a far sale')
            end)
        end

        it('buys several and sells several at the shop', function()
            local row = atShop()

            buy(player, row.index, 2)
            buy(player, row.index, 1)
            local spent = 3 * row.price
            assert(player:getItemCount(feather) == 3, 'three feathers should have been bought, have ' .. player:getItemCount(feather))
            assert(player:getGil() == 10000 - spent, string.format('the feathers should cost %d, gil is %d', spent, player:getGil()))

            local quote = appraise(player, feather, 2)
            assert(quote and quote > 0, 'the merchant should quote the feathers')
            confirmSale(player)
            assert(player:getItemCount(feather) == 1, 'two feathers should have been sold')
            assert(player:getGil() == 10000 - spent + 2 * quote, 'the sale should pay twice the quote')

            local again = appraise(player, feather, 1)
            assert(again == quote, 'the last feather should get the same quote')
            confirmSale(player)
            assert(player:getItemCount(feather) == 0, 'the last feather should have been sold')
            assert(player:getGil() == 10000 - spent + 3 * quote, 'the sales should pay three times the quote')
        end)

        it('buys and sells a few steps from the merchant', function()
            local row = atShop()

            stepAway(player, merchant, 5)
            buy(player, row.index, 1)
            assert(player:getItemCount(feather) == 1 and player:getGil() == 10000 - row.price, 'the feather should have been bought')

            local quote = appraise(player, feather, 1)
            assert(quote and quote > 0, 'the merchant should quote the feather')
            confirmSale(player)
            assert(player:getItemCount(feather) == 0 and player:getGil() == 10000 - row.price + quote, 'the feather should have been sold')
        end)
    end)

    it('buys from a shop that a menu event opens (Regine, Port San d\'Oria)', function()
        spawnIn(xi.zone.PORT_SAN_DORIA)

        player.packets:clear()
        player.entities:gotoAndTrigger('Regine', { eventId = 510, finishOption = 0 }) -- the white magic shop
        assert(not player:isInEvent() and #incoming(player, 0x03E) == 1, 'setup: the menu should open the shop')
        local row = cheapestRow(shopRows(player))

        buy(player, row.index, 1)

        assert(player:getItemCount(row.itemId) == 1, 'the item should have been bought')
        assert(player:getGil() == 10000 - row.price, 'the item should cost its listed price')
    end)

    it('buys from Tomasa (Metalworks) after she walks on along her path, from where the player talked to her', function()
        spawnIn(xi.zone.METALWORKS)
        local merchant = player.entities:get('Tomasa')

        -- Her path runs from z -19 to z -29 (scripts/zones/Metalworks/npcs/Tomasa.lua).
        local function waitUntil(done, what)
            for _ = 1, 120 do
                if done() then
                    return
                end

                xi.test.world:skipTime(1)
            end

            error('setup: ' .. what)
        end

        waitUntil(function()
            return merchant:getZPos() > -19.2
        end, 'Tomasa should reach the north end of her path')

        player.actions:move(merchant:getXPos(), merchant:getYPos(), merchant:getZPos() + 5.5)
        local row = cheapestRow(openShop(player, merchant))

        waitUntil(function()
            return merchant:getZPos() < -28.8
        end, 'Tomasa should walk to the south end of her path')

        local d = player:checkDistance(merchant)
        assert(d > 14, string.format('setup: Tomasa should have walked away from the player, is %.1f yalms off', d))

        buy(player, row.index, 1)

        assert(player:getItemCount(row.itemId) == 1, string.format('the item should have been bought %.1f yalms from Tomasa', d))
        assert(player:getGil() == 10000 - row.price, 'the item should cost its listed price')
    end)
end)
