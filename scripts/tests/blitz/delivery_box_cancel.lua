-----------------------------------
-- Delivery box: a Cancel or a Get never destroys what is in the box
-- src/map/utils/dboxutils.cpp CancelSendingItem and TakeItemFromCell, driven by raw 0x04D packets
-----------------------------------
local ffi = require('ffi')

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

local cmd =
{
    WORK       = 0x01,
    SET        = 0x02,
    SEND       = 0x03,
    CANCEL     = 0x04,
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

-- the wallet's stack size (src/map/items/item_currency.cpp)
local gilCap = 999999999

describe('Delivery box', function()
    ---@type CClientEntityPair
    local sender
    ---@type CClientEntityPair
    local recipient

    -- Sends one 0x04D and returns the 0x04B replies to it
    local function pbx(player, command, boxNo, postWorkNo, itemWorkNo, itemStacks, targetName)
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
        for _, incoming in ipairs(player.packets:getIncoming()) do
            if incoming.type == 0x04B then
                local data  = incoming.data
                local full  = incoming.size >= 0x58
                local reply =
                {
                    command  = data[0x04],
                    slot     = data[0x06],
                    result   = data[0x0C],
                    count    = data[0x0D],
                    newCount = data[0x0E],
                    itemId   = full and data[0x30] + data[0x31] * 0x100 or 0,
                    quantity = full and data[0x38] + data[0x39] * 0x100 + data[0x3A] * 0x10000 + data[0x3B] * 0x1000000 or 0,
                }

                table.insert(replies, reply)
            end
        end

        return replies
    end

    local function replied(replies, command, result)
        for _, reply in ipairs(replies) do
            if reply.command == command and reply.result == result then
                return reply
            end
        end

        return nil
    end

    -- Opens the outgoing box and puts `quantity` from inventory slot `itemWorkNo` (0 is gil) in outgoing slot 0
    local function stage(itemWorkNo, quantity)
        pbx(sender, cmd.POST_CLOSE)
        assert(replied(pbx(sender, cmd.DELI_OPEN), cmd.DELI_OPEN, 1), 'outgoing box did not open')
        pbx(sender, cmd.WORK, box.OUTGOING)

        local set = pbx(sender, cmd.SET, box.OUTGOING, 0, itemWorkNo, quantity, recipient:getName())
        assert(replied(set, cmd.SET, 1), 'the stack was not put in the outgoing box')
    end

    -- Reopens a box and returns what the server loads into it from the database: { count, [slot] = { itemId, quantity } }
    local function reopen(player, boxNo)
        pbx(player, cmd.POST_CLOSE)
        pbx(player, boxNo == box.OUTGOING and cmd.DELI_OPEN or cmd.POST_OPEN)

        local contents = { count = 0 }
        for _, reply in ipairs(pbx(player, cmd.WORK, boxNo)) do
            if reply.command == cmd.WORK then
                contents.count = reply.count
                if reply.itemId ~= 0 then
                    contents[reply.slot] = { itemId = reply.itemId, quantity = reply.quantity }
                end
            end
        end

        return contents
    end

    -- Deliveries waiting for the recipient
    local function waiting()
        pbx(recipient, cmd.POST_CLOSE)
        pbx(recipient, cmd.POST_OPEN)

        local check = replied(pbx(recipient, cmd.CHECK, box.INCOMING), cmd.CHECK, 1)
        assert(check, 'the incoming box did not answer the check')

        return check.newCount
    end

    -- The recipient moves the first waiting delivery into incoming slot 0
    local function receive()
        reopen(recipient, box.INCOMING)
        pbx(recipient, cmd.CHECK, box.INCOMING)
        assert(replied(pbx(recipient, cmd.RECV, box.INCOMING, 0, 1), cmd.RECV, 2), 'no delivery to receive')
    end

    local function cancel()
        return pbx(sender, cmd.CANCEL, box.OUTGOING, 0)
    end

    before_each(function()
        sender    = xi.test.world:spawnPlayer({ zone = xi.zone.WINDURST_WOODS })
        recipient = xi.test.world:spawnPlayer({ zone = xi.zone.WINDURST_WOODS })

        for _, player in ipairs({ sender, recipient }) do
            if player:isInEvent() then
                player.events:finish()
            end

            player:gotoMogHouse(xi.zone.WINDURST_WOODS)
            if player:isInEvent() then
                player.events:finish()
            end

            assert(player:inMogHouse(), 'setup: the player should be in its Mog House')
            player:setGil(1000)
        end
    end)

    describe('Cancel of a stack that was never sent', function()
        it('returns the gil to the wallet and leaves no row', function()
            stage(0, 100)
            assert(sender:getGil() == 900, string.format('expected 900 gil after staging 100, has %d', sender:getGil()))

            cancel()
            assert(sender:getGil() == 1000, string.format('expected the 100 staged gil back (1000), has %d', sender:getGil()))

            -- the slot is empty now, so another Cancel or a Get adds nothing
            cancel()
            pbx(sender, cmd.GET, box.OUTGOING, 0)
            assert(sender:getGil() == 1000, string.format('a repeated Cancel or Get paid out again: %d gil', sender:getGil()))

            local outbox = reopen(sender, box.OUTGOING)
            assert(outbox.count == 0 and not outbox[0], 'the staged gil is still in the outgoing box')

            cancel()
            assert(sender:getGil() == 1000, string.format('a Cancel after reopening paid out again: %d gil', sender:getGil()))
        end)

        it('returns an item to the inventory and leaves no row', function()
            sender:addItem(xi.item.CHOCOBO_FEATHER)
            stage(sender:findItem(xi.item.CHOCOBO_FEATHER, xi.inv.INVENTORY):getSlotID(), 1)
            assert(sender:getItemCount(xi.item.CHOCOBO_FEATHER) == 0, 'the feather should be in the outgoing box')

            cancel()
            assert(sender:getItemCount(xi.item.CHOCOBO_FEATHER) == 1, 'the cancelled feather did not come back')
            assert(reopen(sender, box.OUTGOING).count == 0, 'the staged feather is still in the outgoing box')
        end)

        it('keeps an item in the box while the inventory is full', function()
            sender:addItem(xi.item.CHOCOBO_FEATHER)
            stage(sender:findItem(xi.item.CHOCOBO_FEATHER, xi.inv.INVENTORY):getSlotID(), 1)

            for _ = 1, 100 do
                if sender:getFreeSlotsCount() == 0 then
                    break
                end

                sender:addItem(xi.item.BRONZE_SWORD)
            end

            assert(sender:getFreeSlotsCount() == 0, 'setup: the inventory should be full')

            cancel()
            assert(sender:getItemCount(xi.item.CHOCOBO_FEATHER) == 0, 'the feather went into a full inventory')
            local outbox = reopen(sender, box.OUTGOING)
            assert(outbox[0] and outbox[0].itemId == xi.item.CHOCOBO_FEATHER, 'the feather should still be in the outgoing box')

            sender:delItem(xi.item.BRONZE_SWORD, 1)
            cancel()
            assert(sender:getItemCount(xi.item.CHOCOBO_FEATHER) == 1, 'the feather did not come back once there was room')
            assert(reopen(sender, box.OUTGOING).count == 0, 'the feather is still in the outgoing box')
        end)
    end)

    describe('Cancel of a sent stack', function()
        it('only calls the delivery back, and the gil is paid back once', function()
            stage(0, 100)
            assert(replied(pbx(sender, cmd.SEND, box.OUTGOING, 0), cmd.SEND, 1), 'the gil was not sent')
            assert(waiting() == 1, 'the recipient should have one delivery waiting')

            assert(replied(cancel(), cmd.CANCEL, 1), 'the send was not cancelled')
            assert(sender:getGil() == 900, string.format('cancelling a send should not pay anything back yet, has %d gil', sender:getGil()))
            assert(waiting() == 0, 'the recipient still has the delivery')

            local outbox = reopen(sender, box.OUTGOING)
            assert(outbox[0] and outbox[0].itemId == xi.item.GIL and outbox[0].quantity == 100, 'the 100 gil should be back in outgoing slot 0')

            -- unsent again, so the next Cancel pays it back, and nothing after that pays twice
            cancel()
            assert(sender:getGil() == 1000, string.format('expected the 100 gil back (1000), has %d', sender:getGil()))

            cancel()
            pbx(sender, cmd.GET, box.OUTGOING, 0)
            assert(sender:getGil() == 1000, string.format('the gil was paid back twice: %d', sender:getGil()))
            assert(reopen(sender, box.OUTGOING).count == 0, 'the gil is still in the outgoing box')
            assert(recipient:getGil() == 1000, string.format('the recipient should not have been paid, has %d gil', recipient:getGil()))
        end)

        it('pays nothing back once the recipient has taken the gil', function()
            stage(0, 100)
            assert(replied(pbx(sender, cmd.SEND, box.OUTGOING, 0), cmd.SEND, 1), 'the gil was not sent')

            receive()
            assert(replied(pbx(recipient, cmd.GET, box.INCOMING, 0), cmd.GET, 1), 'the recipient did not take the gil')
            assert(recipient:getGil() == 1100, string.format('expected the recipient at 1100 gil, has %d', recipient:getGil()))

            cancel()
            pbx(sender, cmd.GET, box.OUTGOING, 0)
            reopen(sender, box.OUTGOING)
            cancel()
            pbx(sender, cmd.GET, box.OUTGOING, 0)
            assert(sender:getGil() == 900, string.format('the sender got back gil the recipient already took: %d', sender:getGil()))
        end)
    end)

    describe('Gil past the cap', function()
        it('keeps the gil in the outgoing box until it fits under the cap', function()
            stage(0, 100)
            sender:setGil(gilCap - 99)

            cancel()
            assert(sender:getGil() == gilCap - 99, string.format('expected the wallet left at %d, has %d', gilCap - 99, sender:getGil()))
            local outbox = reopen(sender, box.OUTGOING)
            assert(outbox[0] and outbox[0].itemId == xi.item.GIL and outbox[0].quantity == 100, 'the 100 gil should still be in outgoing slot 0')

            sender:setGil(gilCap - 100)
            cancel()
            assert(sender:getGil() == gilCap, string.format('expected the wallet at the cap, has %d', sender:getGil()))
            assert(reopen(sender, box.OUTGOING).count == 0, 'the gil is still in the outgoing box')
        end)

        it('keeps received gil in the incoming box until it fits under the cap', function()
            stage(0, 100)
            assert(replied(pbx(sender, cmd.SEND, box.OUTGOING, 0), cmd.SEND, 1), 'the gil was not sent')
            recipient:setGil(gilCap - 99)

            receive()
            assert(not replied(pbx(recipient, cmd.GET, box.INCOMING, 0), cmd.GET, 1), 'the gil should not be handed over past the cap')
            assert(recipient:getGil() == gilCap - 99, string.format('expected the wallet left at %d, has %d', gilCap - 99, recipient:getGil()))
            local inbox = reopen(recipient, box.INCOMING)
            assert(inbox[0] and inbox[0].itemId == xi.item.GIL and inbox[0].quantity == 100, 'the 100 gil should still be in incoming slot 0')

            recipient:setGil(gilCap - 100)
            assert(replied(pbx(recipient, cmd.GET, box.INCOMING, 0), cmd.GET, 1), 'the gil was not handed over once it fit')
            assert(recipient:getGil() == gilCap, string.format('expected the wallet at the cap, has %d', recipient:getGil()))
        end)
    end)
end)
