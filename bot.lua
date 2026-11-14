--管理机器人的物品栏与位置
---@diagnostic disable: inject-field, undefined-field, assign-type-mismatch, duplicate-set-field, need-check-nil
local component = require("component")
local computer = require("computer")
local robot = require("robot")
local event = require("event")

local analyzeGenes = require("analyzeGenes")

local inventory_controller = component.inventory_controller
local upgrade_me = component.upgrade_me
local database = component.database

local M = {}
local inventorySize = robot.inventorySize()
if inventorySize < 32 then
    error("物品栏升级过少")
end

--监听inventory_changed事件，维护物品栏映射表
M.inventory, M.inventoryLabel = {}, nil
local function cacheStack(slot, stack, label)
    if stack then
        local success, result = pcall(analyzeGenes, stack)
        if success then
            M.inventory[slot] = result
        else
            M.inventory[slot] = stack
            M.inventory[slot].type = "others"
        end
        M.inventory[slot].inventoryLabel = label
    else
        M.inventory[slot] = nil
    end
end
function M.updateInventory(_, slot)
    cacheStack(slot, inventory_controller.getStackInInternalSlot(slot), M.inventoryLabel)
    os.sleep(0)
    return true
end
event.listen("inventory_changed", M.updateInventory)

--robot库物品栏操作函数重定向
local t, e = robot.transferTo, inventory_controller.equip
function M.equip()
    local previousLabel = M.inventoryLabel
    M.inventoryLabel = M.inventory[0] and M.inventory[0].inventoryLabel
    M.inventory[0] = M.inventory[robot.select()]
    e()
    os.sleep(0)
    M.inventoryLabel = previousLabel
end
function M.transfer(previousSlot, targetSlot)
    if not M.inventory[previousSlot]then
        return false
    end
    local previousSlotLabel, targetSlotLabel = M.inventory[previousSlot] and M.inventory[previousSlot].inventoryLabel, M.inventory[targetSlot] and M.inventory[targetSlot].inventoryLabel
    robot.select(previousSlot)
    local result = t(targetSlot)
    os.sleep(0.1)
    if M.inventory[targetSlot] then
        M.inventory[targetSlot].inventoryLabel = previousSlotLabel
    end
    if M.inventory[previousSlot] then
        M.inventory[previousSlot].inventoryLabel = targetSlotLabel
    end
    return result
end
robot.transferTo, inventory_controller.equip = M.transfer, M.equip
local inventoryChangerList = {
    {robot, "drop"}, {robot, "dropDown"}, {robot, "dropUp"}, {robot, "suck"}, {robot, "suckDown"}, {robot, "suckUp"},
    {inventory_controller, "dropIntoSlot"}, {inventory_controller, "suckFromSlot"}, {upgrade_me, "requestItems"}
}
for _, pack in pairs(inventoryChangerList) do--对于可能改变物品栏的函数，在结束后执行一个sleep(0.01)等待异步操作更新物品栏映射表
    local lib, funcName = pack[1], pack[2]
    local previousFunc = lib[funcName]
    lib[funcName] = function(...)
        local result = previousFunc(...)
        os.sleep(0.01)
        return result
    end
end

--robot库移动函数重定向
local position,direction = {x=0,y=1,z=0},{x=0,z=-1}
local f, b, u, d, l, r = robot.forward, robot.back, robot.up, robot.down, robot.turnLeft, robot.turnRight
function M.up()
    while not u() do
        os.sleep(0)
    end
    position.y = position.y + 1
end
function M.down()
    while not d() do
        os.sleep(0)
    end
    position.y = position.y - 1
end
function M.forward()
	while not f() do
        os.sleep(0)
    end
	position.x=position.x+direction.x
	position.z=position.z+direction.z
end
function M.back()
    while not b() do
        os.sleep(0)
    end
    position.x = position.x - direction.x
    position.z = position.z - direction.z
end
robot.forward, robot.back, robot.up, robot.down = M.forward, M.back, M.up, M.down
function M.turnLeft()
    l()
    direction.x, direction.z = -direction.z, direction.x
end
function M.turnRight()
    r()
    direction.x, direction.z = direction.z, -direction.x
end
robot.turnLeft, robot.turnRight = M.turnLeft, M.turnRight
function M.turnTo(targetX, targetZ)
    if math.abs(targetX) + math.abs(targetZ) ~= 1 or targetX * targetZ ~= 0 then
        error("错误的调用bot.turnTo()")
    end
	if direction.x ~= targetX or direction.z ~= targetZ then
		if (direction.x ~= 0 and direction.x+targetX == 0) or (direction.z ~= 0 and direction.z + targetZ == 0) then
			M.turnRight() M.turnRight()
		elseif direction.x == targetZ and direction.z + targetX == 0 then
			M.turnLeft()
		elseif direction.z == targetX and direction.x + targetZ == 0 then
			M.turnRight()
		end
	end
end
function M.moveXZTo(targetX, targetZ)
    local movedX = false
    local function moveX()
        if position.x > targetX then
            M.turnTo(-1,0)
            for i=1,position.x-targetX do
                M.forward()
            end
        elseif position.x < targetX then
            M.turnTo(1,0)
            for i=1,targetX-position.x do
                M.forward()
            end
        end
        movedX = true
    end
    if direction.x * (targetX - position.x) > 0 or direction.z * (targetZ - position.z) < 0 then
        moveX()
    end
	if position.z > targetZ then
		M.turnTo(0,-1)
		for i=1,position.z- targetZ do
            M.forward()
        end
	elseif position.z < targetZ then
		M.turnTo(0,1)
		for i=1, targetZ -position.z do
            M.forward()
        end
	end
    if not movedX then
        moveX()
    end
end
function M.moveYTo(targetY)
    if targetY > position.y then
        for i=1,targetY-position.y do
            M.up()
        end
    elseif targetY < position.y then
        for i=1,position.y-targetY do
            M.down()
        end
    end
end

--充电
function M.charge()
    local previousPosition = {x=position.x, y=position.y, z=position.z}
    local previousDirection = {x=direction.x, z=direction.z}
    if computer.energy() < 5000 then
        M.moveYTo(2)
        M.moveXZTo(0,0)
        M.moveYTo(1)
        local targetEnergy = computer.maxEnergy() - 100
        while computer.energy() < targetEnergy do
            os.sleep(0.5)
        end
        M.moveYTo(2)
        M.moveXZTo(previousPosition.x, previousPosition.z)
        M.moveYTo(previousPosition.y)
        M.turnTo(previousDirection.x, previousDirection.z)
    end
    return true
end
event.timer(120, M.charge, math.huge)

--物品栏管理函数
function M.getEmptySlotCount()
    local count = 0
    for i=1,inventorySize do
        if not M.inventory[i] then
            count = count + 1
        end
    end
    return count
end
function M.selectEmptySlot()
    for i=1,inventorySize do
        if not M.inventory[i] and robot.count(i) == 0 then
            return robot.select(i)
        end
    end
    return nil
end
function M.selectUsedSlot()
    for i=1,inventorySize do
        if M.inventory[i] and robot.count(i) > 0 then
            return robot.select(i)
        end
    end
    return nil
end
function M.getItemsWithLabel(inventoryLabel)
    local result = {}
    for i=1,inventorySize do
        if M.inventory[i] and M.inventory[i].inventoryLabel == inventoryLabel then
            table.insert(result, i)
        end
    end
    return result
end
function M.clearItem(inventoryLabel)
    for i=1,inventorySize do
        if M.inventory[i] and M.inventory[i].inventoryLabel == inventoryLabel then
            if M.inventory[i].type == "beePrincess" or M.inventory[i].type == "beeDrone" then
                robot.select(i)
                robot.dropUp()
            else
                robot.select(i)
                upgrade_me.sendItems()
            end
        end
    end
end
local function matchesItem(stack, filter)
    return stack and (not filter.name or stack.name == filter.name)
        and (filter.damage == nil or stack.damage == filter.damage)
        and (filter.tag == nil or stack.tag == filter.tag)
        and (not filter.label or stack.label == filter.label)
end

local function sameItem(a, b)
    return a and b and a.name == b.name and a.damage == b.damage and a.tag == b.tag
        and (a.tag ~= nil or not (a.hasTag or b.hasTag))
end

local function readSlot(slot)
    return inventory_controller.getStackInInternalSlot(slot)
end

local function refreshSlot(slot, stack, previous, previousLabel)
    local label = M.inventoryLabel
    if sameItem(stack, previous) then
        label = previousLabel
    end
    cacheStack(slot, stack, label)
end

local function findDatabaseItem(item, stacks)
    local exact = {name = item.name, damage = item.damage, tag = item.tag, hasTag = item.hasTag}
    database.clear(1)
    upgrade_me.store(exact, database.address, 1, 1)
    if sameItem(database.get(1), item) then return 1 end
    if not item.tag then return nil end

    -- 兼容不能通过 Lua 过滤表匹配二进制 NBT 的驱动。
    local count = 0
    for _, stack in ipairs(stacks) do
        if stack.name == item.name and stack.damage == item.damage and stack.label == item.label then
            count = count + 1
        end
    end
    local slots = 0
    for slot = 1, math.min(count, 81) do
        local ok = pcall(database.clear, slot)
        if not ok then break end
        slots = slot
    end
    local byLabel = {name = item.name, damage = item.damage, label = item.label}
    upgrade_me.store(byLabel, database.address, 1, slots)
    for slot = 1, slots do
        if sameItem(database.get(slot), item) then return slot end
    end
end

local function checkItem(filter, request)
    request = type(request) == "number" and request or (request and 1 or 0)
    if request < 0 or request % 1 ~= 0 then
        error("取物数量必须是非负整数")
    end

    local targetSlot, target, emptySlot
    local matchingSlots = {}
    for slot = 1, inventorySize do
        local stack = readSlot(slot)
        if matchesItem(stack, filter) then
            if request == 0 then return slot end
            if stack.size >= request then
                local cached = M.inventory[slot]
                refreshSlot(slot, stack, cached, cached and cached.inventoryLabel)
                return slot
            end
            table.insert(matchingSlots, slot)
            if (stack.maxSize or 64) >= request and (not target or stack.size > target.size) then
                targetSlot, target = slot, stack
            end
        elseif not stack and not emptySlot then
            emptySlot = slot
        end
    end

    if targetSlot then
        local cached = M.inventory[targetSlot]
        local label = sameItem(cached, target) and cached.inventoryLabel or nil
        for _, slot in ipairs(matchingSlots) do
            if slot ~= targetSlot then
                local source = readSlot(slot)
                if sameItem(source, target) then
                    local sourceCache = M.inventory[slot]
                    local sourceLabel = sameItem(sourceCache, source) and sourceCache.inventoryLabel or nil
                    robot.select(slot)
                    t(targetSlot, request - target.size)
                    os.sleep(0)
                    refreshSlot(slot, readSlot(slot), source, sourceLabel)
                    local received = readSlot(targetSlot)
                    refreshSlot(targetSlot, received, target, label)
                    if not sameItem(received, target) then return nil end
                    target = received
                    if target.size >= request then return targetSlot end
                end
            end
        end
    end

    local networkFilter = {name = filter.name, damage = filter.damage, label = filter.label}
    local stacks = upgrade_me.getItemsInNetwork(networkFilter)
    if not stacks then error("超出ME网络范围") end
    local item
    for _, stack in ipairs(stacks) do
        if matchesItem(stack, filter) and stack.size > 0 then
            if request == 0 then return true end
            if target and sameItem(stack, target) then
                item = stack
                break
            end
            if (not item or item.size < request and stack.size >= request) and (stack.maxSize or 64) >= request
                and (not target or emptySlot and stack.size >= request) then
                item = stack
            end
        end
    end
    if not item then return nil end

    if not sameItem(item, target) then targetSlot = emptySlot end
    if not targetSlot then error("物品栏已满") end

    local before = readSlot(targetSlot)
    if before and not sameItem(before, item) then return nil end
    local cached = M.inventory[targetSlot]
    local label = cached and cached.inventoryLabel
    if not before or before.size < request then
        local dbSlot = findDatabaseItem(item, stacks)
        if not dbSlot or robot.select(targetSlot) ~= targetSlot then return nil end
        before = readSlot(targetSlot)
        if before and not sameItem(before, item) then return nil end
        local missing = request - (before and before.size or 0)
        if missing > 0 then upgrade_me.requestItems(database.address, dbSlot, missing) end
    end
    local received = readSlot(targetSlot)
    refreshSlot(targetSlot, received, cached, label)
    if sameItem(received, item) and received.size >= request then
        return targetSlot
    end
end

function M.checkItem(filter, request)
    if not filter or not filter.name then
        error("错误的调用bot.checkItem()")
    end
    return checkItem(filter, request)
end

function M.checkItemByTag(filter, request)
    if not filter or not filter.tag or not (filter.label or filter.name) then
        error("错误的调用bot.checkItemByTag()")
    end
    return checkItem(filter, request)
end
local crafterArea = {[1]=true,[2]=true,[3]=true,[5]=true,[6]=true,[7]=true,[9]=true,[10]=true,[11]=true}
function M.clearCrafterArea()
    if M.getEmptySlotCount() < 9 then
        return false
    end
    for slot,_ in pairs(crafterArea) do
        if M.inventory[slot] then
            for i=1,inventorySize do
                if not crafterArea[i] and not M.inventory[i] then
                    M.transfer(slot, i)
                    os.sleep(0)
                end
            end
        end
    end
    return true
end

--初始化物品栏映射表
for i=1,inventorySize do
    M.updateInventory(nil, i)
end
M.equip()
M.equip()

return M

--[[
inventoryName
简易蜂房/蜂箱"tile.for.apiculture"
诱变机"tile.gendustry.mutatron"
基因压印机"tile.gendustry.imprinter"
基因采样机"tile.gendustry.sampler"
基因转换机"tile.gendustry.transposer"
基因复制机"tile.gendustry.replicator"
]]
