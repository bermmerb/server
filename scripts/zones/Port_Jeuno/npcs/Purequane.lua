-----------------------------------
-- Area: Port Jeuno
--  NPC: Purequane
-- !pos -76 8 54 246
-----------------------------------
---@type TNpcEntity
local entity = {}

entity.onTrigger = function(player, npc)
    if
        player:hasKeyItem(xi.keyItem.AIRSHIP_PASS) and
        player:getGil() >= 200
    then
        player:startEvent(38)
    else
        player:startEvent(46)
    end
end

entity.onEventFinish = function(player, csid, option, npc)
    if csid == 38 then
        local zPos = player:getZPos()

        if zPos >= 58 and zPos <= 61 then
            xi.transport.payAirshipFareAtGate(player)
        end
    end
end

return entity
