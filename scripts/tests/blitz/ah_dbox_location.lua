-----------------------------------
-- Auction House (0x04E) and delivery box (0x04D): where they are taken
-- The auction house menu only opens by talking to an auction counter, so its commands are only taken near the counter
-- that opened it (src/map/packets/c2s/0x04e_auc.cpp). On retail the whole delivery box is in the Mog House, the Mog
-- Garden and with a Nomad Moogle; the NPCs next to the auction houses only send (BG-Wiki: Delivery Box, Nomad Moogle,
-- Karlotte). 0x04d_pbx.cpp now takes it outside the Mog House and the mog menu zones only from the send box such an
-- NPC opened. Before, any 0x04E was taken anywhere in an auction house zone, and any 0x04D too, while the item
-- deliverers of the [S] cities, which have no auction house, could not send at all. The negative cases send the
-- packets raw, as a packet tool would.
-----------------------------------
local ffi = require('ffi')

-- 0x04E with its header (src/map/packets/c2s/0x04e_auc.h). Param is AskCommit (Commission, ItemWorkIndex, ItemNo,
-- ItemStacks), LotIn (LimitPrice, ItemWorkIndex, -, ItemStacks) or Bid (BidPrice, ItemNo, -, ItemStacks).
local aucPacket = ffi.typeof([[
    struct {
        uint8_t  header[4];
        uint8_t  Command;
        int8_t   AucWorkIndex;
        int8_t   Result;
        int8_t   ResultStatus;
        uint32_t Param0;
        uint16_t Param1;
        uint16_t Param2;
        uint32_t ItemStacks;
        uint8_t  Parcel[40];
    }
]])

-- 0x04D with its header (src/map/packets/c2s/0x04d_pbx.h)
local pbxPacket = ffi.typeof([[
    struct {
        uint8_t header[4];
        uint8_t Command;
        int8_t  BoxNo;
        int8_t  PostWorkNo;
        int8_t  ItemWorkNo;
        int32_t ItemStacks;
        int8_t  Result;
        int8_t  ResParam1;
        int8_t  ResParam2;
        int8_t  ResParam3;
        uint8_t TargetName[16];
    }
]])

local auc =
{
    OPEN       = 0x02,
    ASK_COMMIT = 0x04,
    INFO       = 0x05,
    WORK_CHECK = 0x0A,
    LOT_IN     = 0x0B,
    SALES_ROW  = 0x0C,
    BID        = 0x0E,
}

local cmd =
{
    WORK       = 0x01,
    SET        = 0x02,
    SEND       = 0x03,
    CHECK      = 0x05,
    RECV       = 0x06,
    GET        = 0x0A,
    DELI_OPEN  = 0x0D,
    POST_OPEN  = 0x0E,
    POST_CLOSE = 0x0F,
}

local box =
{
    NONE     = -1,
    INCOMING = 1,
    OUTGOING = 2,
}

local feather  = xi.item.CHOCOBO_FEATHER
local price    = 100 -- gil asked for the feather
local proceeds = 300 -- gil waiting in the delivery box, as after an auction sale

-- By name, not id: an upstream sync can renumber a zone's NPCs (data/zones/*/npcs.yaml)
local counterName   = 'Auction_Counter' -- Southern San d'Oria: any of the three at its auction house
local lanqueronName = 'Lanqueron'       -- item deliverer next to that auction house
local karlotteName  = 'Karlotte'        -- item deliverer, Bastok Markets [S] (no auction house there)

-- By the Northern San d'Oria gate, about 80 yalms from every counter
local farSpot = { x = 0.0, y = -8.4, z = 50.0 }

local function s8(b)
    return b >= 128 and b - 256 or b
end

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

local function find(replies, command, result)
    for _, reply in ipairs(replies) do
        if reply.command == command and (result == nil or reply.result == result) then
            return reply
        end
    end

    return nil
end

-- Sends one 0x04E and returns the 0x04C replies to it
local function sendAuc(player, command, index, param0, param1, param2, stacks)
    local packet        = aucPacket()
    packet.Command      = command
    packet.AucWorkIndex = index or -1
    packet.Param0       = param0 or 0
    packet.Param1       = param1 or 0
    packet.Param2       = param2 or 0
    packet.ItemStacks   = stacks or 0

    player.packets:clear()
    player.packets:send(0x04E, packet, ffi.sizeof(packet))
    player:tick()

    local replies = {}
    for _, p in ipairs(incoming(player, 0x04C)) do
        table.insert(replies, { command = p.data[0x04], index = s8(p.data[0x05]), result = p.data[0x06], value = u32(p.data, 0x08), itemId = u16(p.data, 0x28) })
    end

    return replies
end

-- Sends one 0x04D and returns the 0x04B replies to it
local function sendPbx(player, command, boxNo, postWorkNo, itemWorkNo, itemStacks, targetName)
    local packet      = pbxPacket()
    packet.Command    = command
    packet.BoxNo      = boxNo or box.NONE
    packet.PostWorkNo = postWorkNo or -1
    packet.ItemWorkNo = itemWorkNo or -1
    packet.ItemStacks = itemStacks or -1
    if targetName then
        ffi.copy(packet.TargetName, targetName, math.min(#targetName, 15))
    end

    player.packets:clear()
    player.packets:send(0x04D, packet, ffi.sizeof(packet))
    player:tick()

    local replies = {}
    for _, p in ipairs(incoming(player, 0x04B)) do
        table.insert(replies, { command = p.data[0x04], slot = s8(p.data[0x06]), result = p.data[0x0C], newCount = s8(p.data[0x0E]) })
    end

    return replies
end

local function spawnIn(zoneId)
    local player = xi.test.world:spawnPlayer({ zone = zoneId })
    if player:isInEvent() then
        player.events:finish()
    end

    return player
end

local function enterMogHouse(player)
    player:setNation(xi.nation.SANDORIA)
    player:gotoMogHouse(xi.zone.SOUTHERN_SAN_DORIA)
    if player:isInEvent() then
        player.events:finish()
    end

    assert(player:inMogHouse(), 'setup: the player should be in its Mog House')
end

-- Moves the player `yalms` east of the NPC
local function standOff(player, npc, yalms)
    player.actions:move(npc:getXPos() + yalms, npc:getYPos(), npc:getZPos())
    local d = player:checkDistance(npc)
    assert(math.abs(d - yalms) < 0.1, string.format('setup: the player should be %.1f yalms from %s, is %.1f', yalms, npc:getName(), d))
end

local function moveToFarSpot(player)
    player.actions:move(farSpot.x, farSpot.y, farSpot.z)
    assert(player:checkDistance(farSpot.x, farSpot.y, farSpot.z) < 0.1, 'setup: the player should be by the gate')
end

local function expectUnchanged(player, gil, feathers, what)
    assert(player:getGil() == gil, string.format('%s: gil should stay %d, is %d', what, gil, player:getGil()))
    assert(player:getItemCount(feather) == feathers, string.format('%s: feathers should stay %d, are %d', what, feathers, player:getItemCount(feather)))
end

describe('Auction House location', function()
    ---@type CClientEntityPair
    local seller
    local counter

    -- Talks to the counter from where the player stands; the client answers the menu with WorkCheck
    local function openAuction(player)
        player.packets:clear()
        player.actions:trigger(counter)
        local opened = false
        for _, p in ipairs(incoming(player, 0x04C)) do
            opened = opened or (p.data[0x04] == auc.OPEN and p.data[0x06] == 1)
        end

        assert(opened, 'setup: talking to the counter should open the auction house menu')
        sendAuc(player, auc.WORK_CHECK, -1)
    end

    local function featherSlot(player)
        return player:findItem(feather, xi.inv.INVENTORY):getSlotID()
    end

    -- The fee the server quotes for the feather (AskCommit), or nil
    local function quote(player)
        local reply = find(sendAuc(player, auc.ASK_COMMIT, -1, price, featherSlot(player), feather, 1), auc.ASK_COMMIT, 1)
        return reply and reply.value or nil
    end

    -- The LotIn result for the feather (1 = put up), or nil
    local function lotIn(player)
        local reply = find(sendAuc(player, auc.LOT_IN, 0, price, featherSlot(player), 0, 1), auc.LOT_IN)
        return reply and reply.result or nil
    end

    -- The Bid result for one feather (1 = bought), or nil
    local function bid(player, amount)
        local reply = find(sendAuc(player, auc.BID, 0, amount, feather, 0, 1), auc.BID)
        return reply and reply.result or nil
    end

    local function expectNoListing(player, what)
        assert(quote(player) == nil, what .. ': there should be no quote')
        assert(lotIn(player) == nil, what .. ': the LotIn should get no answer')
        assert(#sendAuc(player, auc.INFO, -1) == 0, what .. ': the sales status should get no answer')
        expectUnchanged(player, 10000, 1, what)
    end

    local function newBuyer()
        local buyer = spawnIn(xi.zone.SOUTHERN_SAN_DORIA)
        buyer:setGil(10000)
        buyer.entities:moveTo(counter)
        return buyer
    end

    before_each(function()
        seller = spawnIn(xi.zone.SOUTHERN_SAN_DORIA)
        seller:setGil(10000)
        seller:addItem(feather)
        counter = seller.entities:get(counterName)
    end)

    it('takes nothing from a character that never opened the menu, at the counter or by the gate', function()
        seller.entities:moveTo(counter)
        expectNoListing(seller, 'at the counter, never talked to')

        moveToFarSpot(seller)
        expectNoListing(seller, 'by the gate, never talked to')
    end)

    for _, yalms in ipairs({ 25, 40 }) do
        it(string.format('takes no listing %d yalms from the counter that opened the menu', yalms), function()
            seller.entities:moveTo(counter)
            openAuction(seller)

            standOff(seller, counter, yalms)
            expectNoListing(seller, string.format('%d yalms off', yalms))
        end)
    end

    it('takes no bid 40 yalms from the counter that opened the menu', function()
        seller.entities:moveTo(counter)
        openAuction(seller)
        assert(lotIn(seller) == 1, 'setup: the seller should put the feather up')

        local buyer = newBuyer()
        openAuction(buyer)
        standOff(buyer, counter, 40)

        assert(bid(buyer, price) == nil, 'the bid should get no answer')
        assert(buyer:getGil() == 10000 and buyer:getItemCount(feather) == 0, 'the buyer should keep its gil and get no feather')
    end)

    it('takes no listing in the Mog House after opening the menu outside', function()
        seller.entities:moveTo(counter)
        openAuction(seller)

        enterMogHouse(seller)
        seller:setGil(10000)
        expectNoListing(seller, 'in the Mog House')
    end)

    it('lists, reads its sales and sells at the counter', function()
        seller.entities:moveTo(counter)
        openAuction(seller)

        local fee = quote(seller)
        assert(fee and fee > 0, 'the counter should quote a fee')
        assert(lotIn(seller) == 1, 'the feather should be put up')
        assert(seller:getItemCount(feather) == 0, 'the feather should have left the bag')
        assert(seller:getGil() == 10000 - fee, string.format('the fee %d should be paid, gil is %d', fee, seller:getGil()))

        local sales = sendAuc(seller, auc.INFO, -1)
        assert(find(sales, auc.INFO, 1), 'the sales status should answer')
        local row = find(sales, auc.SALES_ROW)
        assert(row and row.itemId == feather, 'the sales status should list the feather')

        local buyer = newBuyer()
        openAuction(buyer)
        assert(bid(buyer, price) == 1, 'the bid should buy a feather')
        assert(buyer:getItemCount(feather) == 1 and buyer:getGil() == 10000 - price, 'the buyer should pay the bid for the feather')
    end)

    it('lists after talking from the edge of talk range and walking a few steps on', function()
        standOff(seller, counter, 5.5)
        openAuction(seller)

        standOff(seller, counter, 15)
        assert(lotIn(seller) == 1, 'the feather should be put up 15 yalms from the counter')
        assert(seller:getItemCount(feather) == 0, 'the feather should have left the bag')
    end)

    it('takes the menu a GM opens with !ah anywhere', function()
        seller:setGMLevel(1)
        moveToFarSpot(seller)
        seller:sendMenu(xi.menuType.AUCTION)

        assert(lotIn(seller) == 1, 'the feather should be put up')
        assert(seller:getItemCount(feather) == 0, 'the feather should have left the bag')
    end)
end)

describe('Delivery box location', function()
    ---@type CClientEntityPair
    local player
    ---@type CClientEntityPair
    local recipient
    local lanqueron

    local function featherSlot()
        return player:findItem(feather, xi.inv.INVENTORY):getSlotID()
    end

    -- Talks to the item deliverer from where the player stands: the server opens the send box (0x04B DeliOpen)
    local function openAtDeliverer(npc)
        player.packets:clear()
        player.actions:trigger(npc)
        local opened = false
        for _, p in ipairs(incoming(player, 0x04B)) do
            opened = opened or (p.data[0x04] == cmd.DELI_OPEN and p.data[0x0C] == 1)
        end

        assert(opened, 'setup: talking to ' .. npc:getName() .. ' should open the send box')
    end

    -- What the client sends to post the feather to the recipient from an open send box
    local function sendFeather()
        local work = sendPbx(player, cmd.WORK, box.OUTGOING)
        local set  = find(sendPbx(player, cmd.SET, box.OUTGOING, 0, featherSlot(), 1, recipient:getName()), cmd.SET, 1)
        local send = set and find(sendPbx(player, cmd.SEND, box.OUTGOING, 0), cmd.SEND, 1)
        return #work, set ~= nil, send ~= nil
    end

    -- How many deliveries wait for `who`, read in its Mog House as the client does
    local function waitingFor(who)
        assert(who:inMogHouse(), 'setup: read the box in the Mog House')
        sendPbx(who, cmd.POST_CLOSE)
        assert(find(sendPbx(who, cmd.POST_OPEN), cmd.POST_OPEN, 1), 'the Mog House should open the receive box')
        sendPbx(who, cmd.WORK, box.INCOMING)
        local check = find(sendPbx(who, cmd.CHECK, box.INCOMING), cmd.CHECK, 1)
        assert(check, 'the receive box should answer the check')
        sendPbx(who, cmd.POST_CLOSE)
        return check.newCount
    end

    -- The raw receive sequence; returns how many 0x04B answers it got
    local function tryToCollect()
        local answers = 0
        for _, packet in ipairs({
            { cmd.POST_OPEN },
            { cmd.WORK, box.INCOMING },
            { cmd.RECV, box.INCOMING, 0, 1 },
            { cmd.GET, box.INCOMING, 0 },
        }) do
            local replies = sendPbx(player, packet[1], packet[2], packet[3], packet[4])
            for _, reply in ipairs(replies) do
                local took = reply.command == cmd.GET and reply.result == 1
                if reply.command == cmd.POST_OPEN or reply.command == cmd.RECV or took then
                    answers = answers + 1
                end
            end
        end

        xi.test.world:skipTime(1)
        return answers
    end

    before_each(function()
        player    = spawnIn(xi.zone.SOUTHERN_SAN_DORIA)
        recipient = spawnIn(xi.zone.SOUTHERN_SAN_DORIA)
        player:setGil(1000)
        player:addItem(feather)
        lanqueron = player.entities:get(lanqueronName)
    end)

    it('opens no receive box in the street, even next to the item deliverer', function()
        SendItemToDeliveryBox(player:getName(), xi.item.GIL, proceeds, 'AH-Jeuno')
        player.entities:moveTo(lanqueron)

        assert(tryToCollect() == 0, 'the receive box should not open in the street')
        assert(#sendPbx(player, cmd.CHECK, box.INCOMING) == 0, 'the check should get no answer')
        assert(player:getGil() == 1000, string.format('gil should stay 1000, is %d', player:getGil()))

        enterMogHouse(player)
        assert(waitingFor(player) == 1, 'the proceeds should still wait in the box')
    end)

    it('opens no send box in the street for the client', function()
        player.entities:moveTo(lanqueron)

        assert(#sendPbx(player, cmd.DELI_OPEN) == 0, 'the send box should not open')
        local work, set = sendFeather()
        assert(work == 0 and not set, 'the send box should take nothing')
        expectUnchanged(player, 1000, 1, 'a send box the client opened')
    end)

    for _, yalms in ipairs({ 25, 40 }) do
        it(string.format('takes nothing %d yalms from the item deliverer that opened the send box, and still closes it', yalms), function()
            player.entities:moveTo(lanqueron)
            openAtDeliverer(lanqueron)

            standOff(player, lanqueron, yalms)
            local work, set = sendFeather()
            assert(work == 0 and not set, 'the send box should take nothing')
            expectUnchanged(player, 1000, 1, string.format('%d yalms off', yalms))

            assert(find(sendPbx(player, cmd.POST_CLOSE), cmd.POST_CLOSE), 'closing the box should still be answered')
        end)
    end

    it('receives nothing through the send box the item deliverer opened', function()
        SendItemToDeliveryBox(player:getName(), xi.item.GIL, proceeds, 'AH-Jeuno')
        player.entities:moveTo(lanqueron)
        openAtDeliverer(lanqueron)

        assert(tryToCollect() == 0, 'the item deliverer only sends')
        assert(player:getGil() == 1000, string.format('gil should stay 1000, is %d', player:getGil()))

        enterMogHouse(player)
        assert(waitingFor(player) == 1, 'the proceeds should still wait in the box')
    end)

    it('sends the feather through the item deliverer, as the client does', function()
        player.entities:moveTo(lanqueron)
        openAtDeliverer(lanqueron)

        local work, set, sent = sendFeather()
        assert(work == 8, 'the send box should list its 8 slots, got ' .. work)
        assert(set and sent, 'the feather should be put in the box and sent')
        assert(player:getItemCount(feather) == 0, 'the feather should have left the bag')
        assert(find(sendPbx(player, cmd.POST_CLOSE), cmd.POST_CLOSE), 'closing the box should be answered')

        enterMogHouse(recipient)
        assert(waitingFor(recipient) == 1, 'the feather should wait for the recipient')
    end)

    it('sends after talking from the edge of talk range and walking a few steps on', function()
        standOff(player, lanqueron, 5.5)
        openAtDeliverer(lanqueron)

        standOff(player, lanqueron, 15)
        local _, set, sent = sendFeather()
        assert(set and sent, 'the feather should be sent 15 yalms from the item deliverer')
        assert(player:getItemCount(feather) == 0, 'the feather should have left the bag')
    end)

    it('receives the proceeds in its Mog House', function()
        SendItemToDeliveryBox(player:getName(), xi.item.GIL, proceeds, 'AH-Jeuno')
        enterMogHouse(player)
        player:setGil(1000)

        assert(find(sendPbx(player, cmd.POST_OPEN), cmd.POST_OPEN, 1), 'the Mog House should open the receive box')
        sendPbx(player, cmd.WORK, box.INCOMING)
        local check = find(sendPbx(player, cmd.CHECK, box.INCOMING), cmd.CHECK, 1)
        assert(check and check.newCount == 1, 'one delivery should wait')
        assert(find(sendPbx(player, cmd.RECV, box.INCOMING, 0, 1), cmd.RECV), 'the delivery should be received into slot 0')
        xi.test.world:skipTime(1)
        assert(find(sendPbx(player, cmd.GET, box.INCOMING, 0), cmd.GET, 1), 'the gil should be taken')
        assert(player:getGil() == 1000 + proceeds, string.format('gil should be %d, is %d', 1000 + proceeds, player:getGil()))
    end)

    it('sends through the item deliverer in Bastok Markets [S], which has no auction house', function()
        player = spawnIn(xi.zone.BASTOK_MARKETS_S)
        player:addItem(feather)
        local karlotte = player.entities:get(karlotteName)
        player.entities:moveTo(karlotte)
        openAtDeliverer(karlotte)

        local work, set, sent = sendFeather()
        assert(work == 8 and set and sent, 'the feather should be sent')
        assert(player:getItemCount(feather) == 0, 'the feather should have left the bag')
        assert(find(sendPbx(player, cmd.POST_CLOSE), cmd.POST_CLOSE), 'closing the box should be answered')
    end)
end)
