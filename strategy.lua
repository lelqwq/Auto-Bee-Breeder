--制定公主蜂和雄蜂的选择策略
local M = {}

local component = require("component")
local robot = require("robot")
local mutations = require("mutations")

local upgrade_me = component.upgrade_me--[[@as table]]

local doUntil = require("doUntil")
local device = require("device")
local bot = require("bot")
local beeData = require("beeData")

local chromosomeList = {"species", "speed", "lifespan", "fertility", "flowering", "flowerProvider", "territory", "effect", "temperatureTolerance", "humidityTolerance", "nocturnal", "tolerantFlyer", "caveDwelling"}

function M.mutate(princessSlot, droneSlot, targetSpecies, mutation)--单步突变
    --参与配对的杂交雄蜂被归为三类：亲代1纯合基因雄蜂（11型）、亲代2纯合基因雄蜂（22型）、双亲杂合基因雄蜂（12型）
    --突变过程存在种族基因存在丢失的可能，此时将返回nil（附带退回的备选雄蜂槽位），待上级函数重新获取可用母本后继续。
    --由于退出时不丢弃已有雄蜂，且已有雄蜂均打上了该品种基因突变标签，故可在下次突变调用中继承已有的雄蜂基因池。
    --1.校验输入
    if bot.inventory[princessSlot].type ~= "beePrincess" or bot.inventory[droneSlot].type ~= "beeDrone" or not targetSpecies or not mutation then
        error(string.format("错误的调用strategy.mutate(%d, %d, %s)",princessSlot, droneSlot, mutation.name))
    end
    for _, chromosome in pairs(chromosomeList) do
        local p1, p2 = bot.inventory[princessSlot][chromosome][1], bot.inventory[princessSlot][chromosome][2]
        local d1, d2 = bot.inventory[droneSlot][chromosome][1], bot.inventory[droneSlot][chromosome][2]
        if chromosome == "species" then
            local function isValid(gene)
                return gene == mutation.parents[1] or gene == mutation.parents[2]
            end
            if not (isValid(p1) and isValid(p2) and isValid(d1) and isValid(d2)) then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂含有非亲本的species基因",princessSlot, droneSlot, mutation.name))
            end
            local hasP1 = p1 == mutation.parents[1] or p2 == mutation.parents[1] or d1 == mutation.parents[1] or d2 == mutation.parents[1]
            local hasP2 = p1 == mutation.parents[2] or p2 == mutation.parents[2] or d1 == mutation.parents[2] or d2 == mutation.parents[2]
            if not (hasP1 and hasP2) then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂无法凑齐突变所需品种",princessSlot, droneSlot, mutation.name))
            end
        elseif chromosome ~= "speed" and chromosome ~= "lifespan" and chromosome ~= "effect" then
            if p1 ~= p2 or d1 ~= d2 or p1 ~= d1 then
                error(string.format("错误的调用strategy.mutate(%d, %d, %s)，参与突变的公主蜂和雄蜂在 %s 基因上不为同种纯合",princessSlot, droneSlot, mutation.name, chromosome))
            end
        end
    end
    local allele1Genes, allele2Genes = {}, {}
    for _, chromosome in pairs(chromosomeList) do
        allele1Genes[chromosome] = bot.inventory[princessSlot][chromosome][1]
        allele2Genes[chromosome] = bot.inventory[droneSlot][chromosome][2]
    end
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "mutate:"..targetSpecies
    bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    local targetBeeSlots = {}
    if mutation.dimension then
    --2.执行突变(手动突变分支)
        device.destruct()
        print(mutation.name.."蜂突变仅在维度 "..mutation.dimension.." 发生，请手动前往指定维度突变，将发生突变的蜜蜂与公主蜂放回物品栏")
        while true do
            local input
            while input ~= "Y" and input ~= "y" do
                io.write("确认突变完成并检查物品栏[Y/n]:")
                input = io.read()
                if input == "N" or input == "n" then
                    error("已取消突变")
                end
            end
            princessSlot = nil
            targetBeeSlots = {}
            for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
                if bot.inventory[slot].name == "Forestry:beePrincessGE" then
                    if princessSlot then
                        princessSlot = "错误：出现了两只公主蜂"
                        break
                    end
                    princessSlot = slot
                    if bot.inventory[slot].species[1] == targetSpecies or bot.inventory[slot].species[2] == targetSpecies then
                        table.insert(targetBeeSlots, 1, slot)
                    end
                end
                if bot.inventory[slot].name == "Forestry:beeDroneGE" and (bot.inventory[slot].species[1] == targetSpecies or bot.inventory[slot].species[2] == targetSpecies) then
                    table.insert(targetBeeSlots, slot)
                end
            end
            if next(targetBeeSlots) and type(princessSlot) == "number" then
                break
            else
                if type(princessSlot) == "string" then
                    print("错误：出现了两只公主蜂")
                elseif type(princessSlot) == "number" then
                    print("未找到突变成功的蜜蜂")
                else
                    print("未找到公主蜂")
                end
            end
        end
    else
    --2.执行突变(自动突变分支)
        if mutation.foundation and not bot.checkItem({name = mutation.foundation.name, damage = mutation.foundation.damage}) then
            doUntil(function ()
                return bot.checkItem({name = mutation.foundation.name, damage = mutation.foundation.damage})
            end, "缺少突变所需的基石："..mutation.foundation.label)
        end
        local function nextGeneration(droneSlot)--追踪公主蜂
            device.nextGeneration(princessSlot, droneSlot, mutation)
            princessSlot = nil
            for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
                if bot.inventory[slot].type == "beePrincess" then
                    if princessSlot then
                        error("错误的调用strategy.mutate().nextGeneration，突变过程中出现了两只公主蜂")
                    end
                    princessSlot = slot
                end
            end
            if not princessSlot then
                error("错误的调用strategy.mutate().nextGeneration，突变过程中未找到公主蜂")
            end
        end
        nextGeneration(droneSlot)
        droneSlot = nil
        local allele11, allele12, allele22 = {}, {}, {}
        while true do
            targetBeeSlots = {}
            allele11, allele12, allele22 = {}, {}, {}
            for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
                if bot.inventory[slot].type == "beeDrone" then
                    local d1, d2 = bot.inventory[slot].species[1], bot.inventory[slot].species[2]
                    if d1 == targetSpecies or d2 == targetSpecies then
                        table.insert(targetBeeSlots, slot)
                    elseif (d1 == mutation.parents[1] and d2 == mutation.parents[2]) or (d1 == mutation.parents[2] and d2 == mutation.parents[1]) then
                        table.insert(allele12, slot)
                    elseif d1 == mutation.parents[1] and d2 == mutation.parents[1] then
                        table.insert(allele11, slot)
                    elseif d1 == mutation.parents[2] and d2 == mutation.parents[2] then
                        table.insert(allele22, slot)
                    else
                        robot.select(slot)
                        robot.dropUp()
                    end
                end
            end
            --丢弃杂蜂
            for _, allele in pairs({allele11, allele12, allele22}) do
                for i=#allele,4,-1 do
                    robot.select(allele[i])
                    robot.dropUp()
                    table.remove(allele, i)
                end
            end
            if bot.inventory[princessSlot].species[1] == targetSpecies or bot.inventory[princessSlot].species[2] == targetSpecies then
                table.insert(targetBeeSlots, 1, princessSlot)
            end
            if #targetBeeSlots > 0 then
                break
            end
            if p1 == p2 then
                if p1 == mutation.parents[1] then
                    local droneSlot = allele22[1] or allele12[1]
                    if droneSlot then
                        nextGeneration(droneSlot)
                    else
                        bot.inventoryLabel = previousLabel
                        return nil, princessSlot
                    end
                elseif p1 == mutation.parents[2] then
                    local droneSlot = allele11[1] or allele12[1]
                    if droneSlot then
                        nextGeneration(droneSlot)
                    else
                        bot.inventoryLabel = previousLabel
                        return nil, princessSlot
                    end
                else
                    bot.inventoryLabel = previousLabel
                    return nil, princessSlot, allele22[1] or allele12[1]
                end
            elseif (p1 == mutation.parents[1] and p2 == mutation.parents[2]) or (p1 == mutation.parents[2] and p2 == mutation.parents[1]) then
                local lack11 = #allele11 == 1 and robot.count(allele11[1]) == 1
                local lack22 = #allele22 == 1 and robot.count(allele22[1]) == 1
                local droneSlot
                if #allele11 == 0 or #allele22 == 0 then
                    droneSlot = allele12[1] or allele11[1] or allele22[1]
                elseif lack11 and not lack22 then
                    droneSlot = allele11[1] or allele12[1] or allele22[1]
                elseif lack22 and not lack11 then
                    droneSlot = allele22[1] or allele12[1] or allele11[1]
                else
                    droneSlot = allele12[1] or allele11[1] or allele22[1]
                end
                if droneSlot then
                    nextGeneration(droneSlot)
                else
                    bot.inventoryLabel = previousLabel
                    return nil, princessSlot
                end
            else
                bot.inventoryLabel = previousLabel
                return nil, princessSlot, allele12[1] or allele22[1] or allele11[1]
            end
        end
    end
    --3.丢弃杂蜂并返回
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        local isTarget = false
        for _, tSlot in pairs(targetBeeSlots) do
            if slot == tSlot then
                isTarget = true
                break
            end
        end
        if not isTarget and slot ~= princessSlot then
            robot.select(slot)
            if bot.inventory[slot].type == "beeDrone" then
                local isPure1, isPure2 = true, true
                for _, chromosome in pairs(chromosomeList) do
                    if bot.inventory[slot][chromosome][1] ~= allele1Genes[chromosome] or bot.inventory[slot][chromosome][2] ~= allele1Genes[chromosome] then
                        isPure1 = false
                    end
                    if bot.inventory[slot][chromosome][1] ~= allele2Genes[chromosome] or bot.inventory[slot][chromosome][2] ~= allele2Genes[chromosome] then
                        isPure2 = false
                    end
                end
                if isPure1 or isPure2 then
                    upgrade_me.sendItems()
                else
                    robot.dropUp()
                end
            else
                robot.dropUp()
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    for _, slot in pairs(targetBeeSlots) do
        bot.inventory[slot].inventoryLabel = previousLabel
    end
    return targetBeeSlots, princessSlot
end

function M.purify(princessSlot, droneSlot, targetGenes, assistantDroneSlot, labelSuffix)--纯化
    --目标基因分为以下四类：生育基因、突变产生的值得保留的新基因（Ⅱ类基因）、样板蜂已有的基因（Ⅲ类基因）、突变产生与样板已有重合的基因（不纳入计算因素）
    --提纯过程存在基因丢失的概率，若导致Ⅱ类基因丢失，则应当返回nil，待上级函数调用冲洗函数将公主蜂洗成母本基因，并调用突变函数进行新一轮的突变获取新的Ⅱ类基因后，再调用此函数继续提纯。
    --由于返回时不丢弃已有雄蜂，且已有雄蜂均打上了该品种基因提纯标签，故可在下一轮调用中继承已有的提纯进度。
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "purify"..targetGenes.species..(labelSuffix or "")
    bot.inventory[princessSlot].inventoryLabel = bot.inventoryLabel
    if droneSlot and droneSlot ~= assistantDroneSlot then
        bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    end
    --1.校验输入，对基因进行分类
    local newGenes, templateGenes = {}, {}
    if bot.inventory[assistantDroneSlot].fertility[1] ~= 4 or bot.inventory[assistantDroneSlot].fertility[2] ~= 4 then
        error("错误的调用strategy("..tostring(princessSlot)..","..tostring(droneSlot)..","..tostring(assistantDroneSlot)..","..tostring(targetGenes.species)..")，样板雄蜂的生育基因必须为纯合4x")
    end
    for _, chromosome in pairs(chromosomeList) do
        local gene = bot.inventory[princessSlot][chromosome]
        --校验目标基因是否存在
        if gene[1] ~= targetGenes[chromosome] and gene[2] ~= targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][2] ~= targetGenes[chromosome] 
        --and bot.inventory[assistantDroneSlot][chromosome][1] ~=  targetGenes[chromosome] and bot.inventory[assistantDroneSlot][chromosome][2] ~= targetGenes[chromosome] or bot.inventory[assistantDroneSlot][chromosome][1] ~= bot.inventory[assistantDroneSlot][chromosome][2] then
        and bot.inventory[assistantDroneSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[assistantDroneSlot][chromosome][2] ~= targetGenes[chromosome] then--初始凛冬雄蜂不纯合的临时解决方案，就这么先跑着吧，哪天出问题了再改
            error("错误的调用strategy.purify("..tostring(princessSlot)..","..tostring(droneSlot)..","..tostring(chromosome).."="..tostring(targetGenes[chromosome])..")")
        --分类
        elseif chromosome ~= "fertility" and not(gene[1] == targetGenes[chromosome] and gene[2] == targetGenes[chromosome] and bot.inventory[droneSlot][chromosome][1] == targetGenes[chromosome]
        and bot.inventory[droneSlot][chromosome][2] == targetGenes[chromosome] and bot.inventory[assistantDroneSlot][chromosome][1] == targetGenes[chromosome]) then
            if bot.inventory[assistantDroneSlot][chromosome][1] == targetGenes[chromosome] then
                table.insert(templateGenes, chromosome)
            else
                table.insert(newGenes, chromosome)
            end
        end
    end
    local function getDrones(highFertilityOnly, includeAssistant)
        local result = {}
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" and (not highFertilityOnly or bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4) then
                table.insert(result, slot)
            end
        end
        if includeAssistant then
            local isPresent = false
            for _, slot in pairs(result) do
                if slot == assistantDroneSlot then isPresent = true break end
            end
            if not isPresent then
                table.insert(result, assistantDroneSlot)
            end
        end
        return result
    end
    local function nextGeneration(droneSlot)--追踪公主蜂
        device.nextGeneration(princessSlot, droneSlot)
        princessSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" then
                if princessSlot then
                    error("错误的调用strategy.purify().nextGeneration，提纯过程中出现了两只公主蜂")
                end
                princessSlot = slot
            end
        end
        if not princessSlot then
            error("错误的调用strategy.purify().nextGeneration，提纯过程中未找到公主蜂")
        end
    end
    --2.提纯生育基因，终止条件是所有生育为纯合4x的雄蜂携带全部Ⅱ类基因且公主蜂生育基因为纯合4x。
    local newGenesWithHighFertility
    local function checkNewGenesWithHighFertility()
        --检查
        newGenesWithHighFertility = {}
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if (bot.inventory[slot].type == "beeDrone" or bot.inventory[slot].type == "beePrincess") and bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                for _,chromosome in pairs(newGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        newGenesWithHighFertility[chromosome] = true
                    end
                end
            end
        end
        for _,chromosome in pairs(newGenes) do
            if not newGenesWithHighFertility[chromosome] then
                return
            end
        end
        if bot.inventory[princessSlot].fertility[1] == 4 and bot.inventory[princessSlot].fertility[2] == 4 then
            newGenesWithHighFertility = "All"
        end
        --丢弃不包含Ⅱ类基因的雄蜂
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" and (bot.inventory[slot].fertility[1] ~= 4 or bot.inventory[slot].fertility[2] ~= 4) then
                local shouldDrop = true
                for _,chromosome in pairs(newGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        shouldDrop = false
                        break
                    end
                end
                if shouldDrop then
                    robot.select(slot)
                    robot.dropUp()
                    while bot.inventory[slot] do
                        os.sleep(0)
                    end
                end
            end
        end
    end
    ::FERTILITY::
    checkNewGenesWithHighFertility()
    while newGenesWithHighFertility ~= "All" do
        local weights = {}
        --若公主蜂携带不在newGenesWithHighFertility表内的Ⅱ类基因，则使用样板雄蜂与公主蜂杂交
        for _,chromosome in pairs(newGenes) do
            if not newGenesWithHighFertility[chromosome] and (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome]) then
                nextGeneration(assistantDroneSlot)
                goto CONTINUE
            end
        end
        --如果发生了基因丢失，直接返回nil
        for _,chromosome in pairs(newGenes) do
            local isLost = true
            if bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                isLost = false
            else
                for _,slot in pairs(getDrones()) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        isLost = false
                        break
                    end
                end
            end
            if isLost then
                bot.inventoryLabel = previousLabel
                return nil, princessSlot
            end
        end
        --若公主蜂生育基因不为纯合4x，则使用样板雄蜂与公主蜂杂交
        if bot.inventory[princessSlot].fertility[1] ~= 4 or bot.inventory[princessSlot].fertility[2] ~= 4 then
            nextGeneration(assistantDroneSlot)
            goto CONTINUE
        end
        --选择包含最多不在newGenesWithHighFertility表内的Ⅱ类基因的雄蜂与公主蜂杂交
        for _,slot in pairs(getDrones()) do
            weights[slot] = 0
            for _,chromosome in pairs(newGenes) do
                if newGenesWithHighFertility[chromosome] then
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] then
                        weights[slot] = weights[slot] + 1
                    end
                    if bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        weights[slot] = weights[slot] + 1
                    end
                elseif bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                    if bot.inventory[slot][chromosome][1] == bot.inventory[slot][chromosome][2] then
                        weights[slot] = weights[slot] + 95
                    else
                        weights[slot] = weights[slot] + 64
                    end
                end
            end
            if bot.inventory[slot].fertility[1] == 4 or bot.inventory[slot].fertility[2] == 4 then
                weights[slot] = weights[slot] + 16
            end
        end
        droneSlot = nil
        for slot,weight in pairs(weights) do
            if droneSlot then
                if weight > weights[droneSlot] then
                    droneSlot = slot
                end
            else
                droneSlot = slot
            end
        end
        nextGeneration(droneSlot)
        ::CONTINUE::
        checkNewGenesWithHighFertility()
    end
    --3.提纯其余所有基因
    local genes = {}
    for _,chromosome in pairs(newGenes) do
        table.insert(genes, chromosome)
    end
    for _,chromosome in pairs(templateGenes) do
        table.insert(genes, chromosome)
    end
    local function dropDrones()
        --处理生育非纯合4x雄蜂
        local lackGenes = {}
        for _,chromosome in pairs(genes) do
            local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
            for _,slot in pairs(getDrones(true)) do
                amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                if amount >= 2 then
                    break
                end
            end
            if amount < 2 then
                table.insert(lackGenes, chromosome)
            end
        end
        for _,slot in pairs(getDrones()) do
            local shouldDrop = true
            if bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                shouldDrop = false
            else
                for _,chromosome in pairs(lackGenes) do
                    if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                        shouldDrop = false
                        break
                    end
                end
            end
            if shouldDrop then
                robot.select(slot)
                robot.dropUp()
                while bot.inventory[slot] do
                    os.sleep(0)
                end
            end
        end
        --处理生育纯合4x雄蜂
        for i = #genes, 1, -1 do
            local pureChromosome = genes[i]
            if bot.inventory[princessSlot][pureChromosome][1] == targetGenes[pureChromosome] and bot.inventory[princessSlot][pureChromosome][2] == targetGenes[pureChromosome] then
                local isPureEnough = true
                for _,chromosome in pairs(genes) do
                    local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                    for _,slot in pairs(getDrones(true)) do
                        if bot.inventory[slot][pureChromosome][1] == targetGenes[pureChromosome] and bot.inventory[slot][pureChromosome][2] == targetGenes[pureChromosome] then
                            amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                        end
                        if amount >= 3 then
                            break
                        end
                    end
                    if amount < 3 then
                        isPureEnough = false
                        break
                    end
                end
                if isPureEnough then
                    for _,slot in pairs(getDrones()) do
                        if bot.inventory[slot][pureChromosome][1] ~= targetGenes[pureChromosome] or bot.inventory[slot][pureChromosome][2] ~= targetGenes[pureChromosome] then
                            robot.select(slot)
                            robot.dropUp()
                            while bot.inventory[slot] do
                                os.sleep(0)
                            end
                        end
                    end
                    table.remove(genes, i)
                end
            end
        end
        --处理生育纯合4x雄蜂
        while true do
            if not next(genes) then break end
            local abundantGenes = {}
            for _,chromosome in pairs(genes) do
                local amount = (bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                for _,slot in pairs(getDrones(true)) do
                    amount = amount + (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                    if amount >= 7 then
                        abundantGenes[chromosome] = true
                        break
                    end
                end
            end
            local weights = {}
            for _,slot in pairs(getDrones()) do
                local hasRareGene = false
                for _,chromosome in pairs(genes) do
                    if not abundantGenes[chromosome] and (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome]) then
                        hasRareGene = true
                        break
                    end
                end
                if not hasRareGene then
                    weights[slot] = 0
                    for _,chromosome in pairs(genes) do
                        if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                            weights[slot] = weights[slot] + 3
                        elseif bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                            weights[slot] = weights[slot] + 1
                        end
                    end
                end
            end
            if next(weights) then
                local minWeightSlot
                for slot, weight in pairs(weights) do
                    if minWeightSlot then
                        if weight < weights[minWeightSlot] then
                            minWeightSlot = slot
                        end
                    else
                        minWeightSlot = slot
                    end
                end
                robot.select(minWeightSlot)
                robot.dropUp()
                while bot.inventory[minWeightSlot] do
                    os.sleep(0)
                end
            else
                break
            end
        end
    end
    while true do
        ::CONTINUE2::
        --若存在纯合目标基因公主蜂与纯合目标基因雄蜂，跳出循环
        local hasPurePrincess = true
        for _,chromosome in pairs(newGenes) do
            if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] then
                hasPurePrincess = false
                break
            end
        end
        if hasPurePrincess then
            for _,chromosome in pairs(templateGenes) do
                if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] then
                    hasPurePrincess = false
                    break
                end
            end
        end
        if hasPurePrincess then
            local hasPureDrone = false
            for _,slot in pairs(getDrones(true, true)) do
                if bot.inventory[slot] and bot.inventory[slot].type == "beeDrone" and bot.inventory[slot].fertility[1] == 4 and bot.inventory[slot].fertility[2] == 4 then
                    local isPure = true
                    for _,chromosome in pairs(newGenes) do
                        if bot.inventory[slot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[slot][chromosome][2] ~= targetGenes[chromosome] then
                            isPure = false
                            break
                        end
                    end
                    if isPure then
                        for _,chromosome in pairs(templateGenes) do
                            if bot.inventory[slot][chromosome][1] ~= targetGenes[chromosome] or bot.inventory[slot][chromosome][2] ~= targetGenes[chromosome] then
                                isPure = false
                                break
                            end
                        end
                    end
                    if isPure then
                        droneSlot = slot
                        hasPureDrone = true
                        break
                    end
                end
            end
            if hasPureDrone then
                break
            end
        end
        dropDrones()
        --统计每个基因的纯合和杂合数量
        local statistics = {}
        for _,chromosome in pairs(genes) do
            statistics[chromosome] = {0, 0}
        end
        for _,slot in pairs(getDrones(true, #newGenes==0)) do
            for _,chromosome in pairs(genes) do
                if bot.inventory[slot][chromosome][1] == targetGenes[chromosome] or bot.inventory[slot][chromosome][2] == targetGenes[chromosome] then
                    if bot.inventory[slot][chromosome][1] == bot.inventory[slot][chromosome][2] then
                        statistics[chromosome][1] = statistics[chromosome][1] + bot.inventory[slot].size
                    else
                        statistics[chromosome][2] = statistics[chromosome][2] + bot.inventory[slot].size
                    end
                end
            end
        end
        --若发生Ⅱ类基因丢失，退回到生育基因提纯阶段
        for _,chromosome in pairs(newGenes) do
            if bot.inventory[princessSlot][chromosome][1] ~= targetGenes[chromosome] and bot.inventory[princessSlot][chromosome][2] ~= targetGenes[chromosome] and statistics[chromosome] and statistics[chromosome][1] == 0 and statistics[chromosome][2] == 0 then
                goto FERTILITY
            end
        end
        --若雄蜂中无Ⅲ类基因，则与样板雄蜂杂交
        for _,count in pairs(statistics) do
            if count[1] == 0 and count[2] == 0 then
                nextGeneration(assistantDroneSlot)
                goto CONTINUE2
            end
        end
        --根据公主蜂对应基因的基因型与雄蜂基因统计结果计算权重
        local weights = {}
        for _,slot in pairs(getDrones(true, #newGenes==0)) do
            weights[slot] = {0, 0, 0, 0, 0, 0}
            for _,chromosome in pairs(genes) do
                local count = (bot.inventory[slot][chromosome][1] == targetGenes[chromosome] and 1 or 0) + (bot.inventory[slot][chromosome][2] == targetGenes[chromosome] and 1 or 0)
                if bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] and bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                    if count == 2 then
                        weights[slot][5] = weights[slot][5] + 1
                    elseif count == 1 then
                        weights[slot][6] = weights[slot][6] + 1
                    end
                elseif bot.inventory[princessSlot][chromosome][1] == targetGenes[chromosome] or bot.inventory[princessSlot][chromosome][2] == targetGenes[chromosome] then
                    if count == 2 then
                        weights[slot][3] = weights[slot][3] + 1
                    elseif count == 1 then
                        weights[slot][4] = weights[slot][4] + 1
                    end
                else
                    if count == 2 and statistics[chromosome][1] > 2 or count == 1 and statistics[chromosome][1] <= 2 then
                        weights[slot][1] = weights[slot][1] + 1
                    elseif count == 1 and statistics[chromosome][1] > 2 or count == 2 and statistics[chromosome][1] <= 2 then
                        weights[slot][2] = weights[slot][2] + 1
                    end
                end
            end
        end
        --选择权重最高的雄蜂与公主蜂杂交
        droneSlot = nil
        for slot,weight in pairs(weights) do
            if droneSlot then
                for i=1,6 do
                    if weights[droneSlot][i] < weight[i] then
                        droneSlot = slot
                        break
                    elseif weights[droneSlot][i] > weight[i] then
                        break
                    end
                end
            else
                droneSlot = slot
            end
        end
        nextGeneration(droneSlot)
    end
    --4.丢弃期间产生的所有杂蜂，将雄蜂数量繁殖到16以上后返回
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        if slot ~= droneSlot and bot.inventory[slot].type == "beeDrone" then
            robot.select(slot)
            robot.dropUp()
        end
    end
    while robot.count(droneSlot--[[@as number]]) < 16 do
        nextGeneration(droneSlot)
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" then
                droneSlot = slot
                break
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    if droneSlot ~= assistantDroneSlot then
        bot.inventory[droneSlot].inventoryLabel = previousLabel
    end
    return droneSlot, princessSlot
end

function M.breedDrones(princessSlot, droneSlot, targetAmount)--繁殖雄蜂
    if bot.inventory[princessSlot].type ~= "beePrincess" or bot.inventory[droneSlot].type ~= "beeDrone" then
        error(string.format("错误的调用strategy.breedDrones(%d, %d, %d)",princessSlot, droneSlot, targetAmount))
    end
    for _, chromosome in pairs(chromosomeList) do
        local p1, p2 = bot.inventory[princessSlot][chromosome][1], bot.inventory[princessSlot][chromosome][2]
        local d1, d2 = bot.inventory[droneSlot][chromosome][1], bot.inventory[droneSlot][chromosome][2]
        if p1 ~= p2 or d1 ~= d2 or p1 ~= d1 then
            error(string.format("错误的调用strategy.breedDrones(%d, %d, %d)，参与繁殖的公主蜂和雄蜂在 %s 基因上不为同种纯合",princessSlot, droneSlot, targetAmount, chromosome))
        end
    end
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "breedDrones:"..bot.inventory[princessSlot].species[1]
    bot.inventory[droneSlot].inventoryLabel = bot.inventoryLabel
    while robot.count(droneSlot) < targetAmount do
        device.nextGeneration(princessSlot, droneSlot)
        princessSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beePrincess" then
                if princessSlot then
                    error("错误的调用strategy.breedDrones()，繁殖过程中出现了两只公主蜂")
                end
                princessSlot = slot
            end
        end
        if not princessSlot then
            error("错误的调用strategy.breedDrones().nextGeneration，繁殖过程中未找到公主蜂")
        end
        droneSlot = nil
        for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
            if bot.inventory[slot].type == "beeDrone" then
                if droneSlot and bot.inventory[slot].tag ~= bot.inventory[droneSlot].tag then
                    error("错误的调用strategy.breedDrones()，繁殖过程中出现了多种基因型的雄蜂")
                end
                droneSlot = slot
            end
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    return princessSlot, droneSlot
end

function M.getAssistantDrones()--获取样板雄蜂
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "breedAssistantDrones"
    local droneTag, princess = beeData.getAssistantBeesTag()
    local droneSlot = bot.checkItem({name="Forestry:beeDroneGE",tag=droneTag}, 16)
    if not droneSlot then
        error("获取样板雄蜂失败：未能提供足够的样板雄蜂")
    end
    local temp = upgrade_me.getItemsInNetwork({label=bot.inventory[droneSlot].label})
    local droneCount = 0
    for _, stack in pairs(temp) do
        if stack.tag == droneTag then
            droneCount = stack.size
            break
        end
    end
    if droneCount < 20 then
        if princess then
            princess = bot.checkItem({name="Forestry:beePrincessGE",tag=princess}, 1)
            if not princess then
                error("获取辅助公主蜂失败：未找到现存的辅助公主蜂")
            end
        else
            --优先复用现存"与样板雄蜂同基因"的纯合公主，避免data丢失后依赖始祖公主重新克隆
            local princessTag = beeData.findAssistantPrincessTag(bot.inventory[droneSlot])
            if princessTag then
                princess = bot.checkItem({name="Forestry:beePrincessGE",tag=princessTag}, 1)
            end
            if not princess then
                princess = beeData.getPrincessTag(true)
                princess = bot.checkItem({name="Forestry:beePrincessGE",tag=princess}, 1)
                if not princess then
                    error("培育样板雄蜂失败：未找到可用的初始公主蜂")
                end
                local targetGenes = {}
                for _, chromosome in pairs(chromosomeList) do
                    targetGenes[chromosome] = bot.inventory[droneSlot][chromosome][1]
                end
                droneSlot, princess = M.purify(princess, droneSlot, targetGenes, droneSlot, ":assistant")
                if not droneSlot then
                    error("培育样板雄蜂过程中发生基因丢失")
                end
            end
        end
        princess, droneSlot = M.breedDrones(princess, droneSlot, 48-droneCount)
        beeData.updateAssistantPrincess(princess)
        robot.select(princess)
        upgrade_me.sendItems()
    end
    bot.inventoryLabel = previousLabel
    local excess = robot.count(droneSlot--[[@as number]]) - 16
    if excess > 0 then
        robot.select(droneSlot--[[@as number]])
        upgrade_me.sendItems(excess)
    end
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    return droneSlot
end

function M.newSpecies(species, mutation)--突变新品种并优化基因
    --扫描更快速度的纯种雄蜂，若发现则更新样板雄蜂，使后续培育采用更快速度
    if beeData.updateBetterTraits() then
        print("发现速度更快的纯种雄蜂，已更新样板雄蜂（原辅助公主蜂配对已失效）")
    end
    --校验输入
    local allele1Tag, allele2Tag = beeData.getDroneTag(mutation.parents[1]), beeData.getDroneTag(mutation.parents[2])
    if not allele1Tag or not allele2Tag then
        error(string.format("错误的调用strategy.newSpecies(%s, %s)，突变所需的亲本品种不存在",species, mutation.name))
    end
    if not mutation.dimension then
        local function confirmMutation()
            io.write("是否继续执行突变？[Y/n]：")
            local answer = io.read()
            if answer ~= "Y" and answer ~= "y" then
                error("突变"..mutation.name.."：已取消")
            end
        end
        if mutation.date then
            print(mutation.name.."蜂突变仅在"..mutation.date[1].."到"..mutation.date[2].."之间发生")
            confirmMutation()
        end
        if mutation.lunar_phase then
            if type(mutation.lunar_phase) == "table" then
                print(mutation.name.."蜂突变仅在月相在"..mutation.lunar_phase[1].."到"..mutation.lunar_phase[2].."之间发生")
            else
                print(mutation.name.."蜂突变仅在月相为"..mutation.lunar_phase.."时发生")
            end
            confirmMutation()
        end
        if mutation.time then
            print(mutation.name.."蜂突变仅在"..mutation.time.."时发生")
            confirmMutation()
        end
    end
    --获取亲本公主蜂与雄蜂
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "newSpecies:"..species
    local allele1Slot, allele2Slot, assistantDroneSlot, princessSlot
    local mutatedBeeList, droneSlot
    local function isTemplatedGenes(tag)
        local genes = require("analyzeGenes")({name="Forestry:beeDroneGE",individual={},tag=tag})
        for chromosome, gene in pairs({flowering=1,flowerProvider="extrabees.flower.rock",fertility=4,territory=1,temperatureTolerance="BOTH_5",humidityTolerance="BOTH_5",nocturnal=true,tolerantFlyer=true,caveDwelling=true}) do
            if genes[chromosome][1] ~= gene or genes[chromosome][2] ~= gene then
                return false
            end
        end
        return true
    end
    local function getOperations(isPrincessParent, isPrincessTemplated, isAllele1Templated, isAllele2Templated)
        --以最小purify步数，快速将公主蜂转换为一亲本纯种，同时让亲本蜂具备模板基因
        if isPrincessParent == 1 and isAllele2Templated then
            return isPrincessTemplated and {} or {"purify(1)"}, false
        end
        if isPrincessParent == 2 and isAllele1Templated then
            return isPrincessTemplated and {} or {"purify(2)"}, true
        end
        if isAllele2Templated then
            return {"purify(1)"}, false
        end
        if isAllele1Templated then
            return {"purify(2)"}, true
        end
        return mutation.parents[1] == mutation.parents[2] and {"purify(1)"} or {"purify(2)", "purify(1)"}, false
    end
    ::GET_PARENT_BEES::
    assistantDroneSlot = M.getAssistantDrones()--[[@as number]]
    princessSlot = bot.checkItem({name="Forestry:beePrincessGE",tag=beeData.getPrincessTag(true)}, 1)
    if not princessSlot then
        error(string.format("突变%s：无法获取公主蜂", mutation.name))
    end
    local isPrincessParent
    if bot.inventory[princessSlot].species[1] == mutation.parents[1] and bot.inventory[princessSlot].species[2] == mutation.parents[1] then
        isPrincessParent = 1
    elseif bot.inventory[princessSlot].species[1] == mutation.parents[2] and bot.inventory[princessSlot].species[2] == mutation.parents[2] then
        isPrincessParent = 2
    end
    allele1Tag, allele2Tag = beeData.getDroneTag(mutation.parents[1]), beeData.getDroneTag(mutation.parents[2])
    local operations, exchanged = getOperations(isPrincessParent, isTemplatedGenes(bot.inventory[princessSlot].tag), isTemplatedGenes(allele1Tag), isTemplatedGenes(allele2Tag))
    allele1Slot = bot.checkItem({name="Forestry:beeDroneGE",tag=allele1Tag}, 16)
    allele2Slot = bot.checkItem({name="Forestry:beeDroneGE",tag=allele2Tag}, 16)
    if not allele1Slot and not allele2Slot then
        error(string.format("突变%s：缺乏必需的亲本雄蜂", mutation.name))
    end
    for _, operation in ipairs(operations) do
        if operation == "purify(1)" then
            allele1Slot, princessSlot = M.purify(princessSlot, allele1Slot, beeData.getTargetGenes(mutation.parents[1]), assistantDroneSlot, ":allele1")
            if not allele1Slot then
                beeData.updateUsingPrincess(princessSlot)
                error("突变"..mutation.name.."亲本雄蜂1基因丢失")
            end
        elseif operation == "purify(2)" then
            allele2Slot, princessSlot = M.purify(princessSlot, allele2Slot, beeData.getTargetGenes(mutation.parents[2]), assistantDroneSlot, ":allele2")
            if not allele2Slot then
                beeData.updateUsingPrincess(princessSlot)
                error("突变"..mutation.name.."亲本雄蜂2基因丢失")
            end
        end
    end
    if exchanged then
        if mutation.parents[1] == mutation.parents[2] then
            allele1Slot = allele2Slot
        elseif allele2Slot ~= assistantDroneSlot then
            robot.select(allele2Slot)
            upgrade_me.sendItems()
        end
        allele2Slot = nil
    else
        if mutation.parents[1] == mutation.parents[2] then
            allele2Slot = allele1Slot
        elseif allele1Slot ~= assistantDroneSlot then
            robot.select(allele1Slot)
            upgrade_me.sendItems()
        end
        allele1Slot = nil
    end
    if bot.inventory[assistantDroneSlot] and assistantDroneSlot ~= (exchanged and allele1Slot or allele2Slot) then
        robot.select(assistantDroneSlot)
        upgrade_me.sendItems()
        assistantDroneSlot = nil
    end
    --执行突变
    if exchanged then
        robot.select(allele1Slot--[[@as number]])
        upgrade_me.sendItems(robot.count(allele1Slot--[[@as number]])-1)
        mutatedBeeList, princessSlot = M.mutate(princessSlot, allele1Slot, species, mutation)
        allele1Slot = nil
    else
        robot.select(allele2Slot--[[@as number]])
        upgrade_me.sendItems(robot.count(allele2Slot--[[@as number]])-1)
        mutatedBeeList, princessSlot = M.mutate(princessSlot, allele2Slot, species, mutation)
        allele2Slot = nil
    end
    if not mutatedBeeList then
        beeData.updateUsingPrincess(princessSlot)
        goto GET_PARENT_BEES
    end
    --纯化突变产生的基因
    while true do
        if not mutatedBeeList[1] then
            beeData.updateUsingPrincess(princessSlot)
            goto GET_PARENT_BEES
        end
        local mDrone = mutatedBeeList[1]
        table.remove(mutatedBeeList, 1)
        assistantDroneSlot = M.getAssistantDrones()--[[@as number]]
        if mDrone == princessSlot then
            mDrone = assistantDroneSlot
        end
        droneSlot, princessSlot = M.purify(princessSlot, mDrone, beeData.getTargetGenes(species), assistantDroneSlot, ":mutated")
        if bot.inventory[assistantDroneSlot] and assistantDroneSlot ~= droneSlot and assistantDroneSlot ~= princessSlot then
            robot.select(assistantDroneSlot)
            upgrade_me.sendItems()
            assistantDroneSlot = nil
        end
        if droneSlot then
            break
        end
    end
    --处理结果
    for _,slot in pairs(mutatedBeeList--[[@as table]]) do
        robot.select(slot)
        robot.dropUp()
    end
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        if slot ~= droneSlot and slot ~= princessSlot then
            robot.select(slot)
            upgrade_me.sendItems()
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    beeData.updateUsingPrincess(princessSlot)
    local updated, oldAssistantPrincessTag = beeData.updateAssistantDrone(droneSlot)
    if updated then
        beeData.updateAssistantPrincess(princessSlot, oldAssistantPrincessTag)
    end
    return droneSlot, princessSlot
end

function M.optimizeSpecies(species)--优化现有品种
    local droneTag = beeData.getDroneTag(species)
    if not droneTag then
        error(string.format("错误的调用strategy.optimizeSpecies(%s)，该品种不存在", species))
    end
    local previousLabel = bot.inventoryLabel
    bot.inventoryLabel = "optimizeSpecies:"..species
    local droneSlot = bot.checkItem({name="Forestry:beeDroneGE",tag=droneTag}, 16)
    if not droneSlot then
        error(string.format("错误的调用strategy.optimizeSpecies(%s)，未找到目标品种的雄蜂", species))
    end
    local princessSlot = bot.checkItem({name="Forestry:beePrincessGE",tag=beeData.getPrincessTag(true)}, 1)
    if not princessSlot then
        error(string.format("错误的调用strategy.optimizeSpecies(%s)，缺少公主蜂", species))
    end
    local assistantDroneSlot = M.getAssistantDrones()
    droneSlot, princessSlot = M.purify(princessSlot, droneSlot, beeData.getTargetGenes(species), assistantDroneSlot, ":optimize")
    for _,slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
        if slot ~= droneSlot and slot ~= princessSlot then
            robot.select(slot)
            upgrade_me.sendItems()
        end
    end
    bot.inventoryLabel = previousLabel
    bot.inventory[droneSlot].inventoryLabel = previousLabel
    bot.inventory[princessSlot].inventoryLabel = previousLabel
    return droneSlot, princessSlot
end

--判断目标品种是否已存在（已初始化且网络中已有该品种雄蜂）
function M.isSpeciesExisting(species)
    return beeData.getDroneTag(species) ~= nil
end

--优化已存在的品种：执行基因优化、存入网络并结束
function M.optimizeExistingSpecies(species)
    print("目标品种已存在，正在优化基因...")
    local droneSlot, princessSlot = M.optimizeSpecies(species)
    robot.select(droneSlot)
    upgrade_me.sendItems()
    robot.select(princessSlot)
    upgrade_me.sendItems()
    print("优化完成！")
    device.destruct()
end

--递归回溯父代，将需要培育的品种及其突变配方填入mutationChain，无法获得的品种填入lackSpecies
function M.calculateMutationChain(species, mutationChain, lackSpecies)
    local visited = {}
    local function addMutation(target)
        if visited[target] then
            return
        end
        visited[target] = true
        if beeData.getDroneTag(target) then
            return
        end
        if not beeData.initialized and (target == "forestry.speciesCultivated" or target == "forestry.speciesCommon") then
            return
        end
        --[[component.database.set(1, "Forestry:beeDroneGE", 0, '{IsAnalyzed:1b,Genome:{Chromosomes:[0:{Slot:0b,UID0:"'..target..'",UID1:"'..target..'"}]}}')
        if bot.checkItem({label=component.database.get(1).label}) then
            return
        end]]--无需检查公主蜂
        if mutations[target] then
            local parents
            if mutations[target][1] then
                parents = mutations[target][1].parents
            else
                parents = mutations[target].parents
            end
            addMutation(parents[1])
            addMutation(parents[2])
            table.insert(mutationChain, {target, mutations[target][1] or mutations[target]})
        else
            table.insert(lackSpecies, target)
            return
        end
    end
    addMutation(species)
end

--校验突变链上每步突变的条件（基石/环境/维度/日期/月相/时间/诱变机）
--返回各类不满足或需人工干预的条件表
function M.checkMutationChain(mutationChain)
    local lackFoundation, lackEnvironmentConditions, requiredDimension, requiredMutatron = {}, {}, {}, {}
    local requiredDate, requiredLunarPhase, requiredTime = {}, {}, {}
    for i = 1, #mutationChain do
        local isSuitable, missingConditions = device.checkMutationEnvironment(mutationChain[i][2])
        if not isSuitable then
            lackEnvironmentConditions[i] = missingConditions
        end
        if mutationChain[i][2].foundation and not bot.checkItem({name=mutationChain[i][2].foundation.name,damage=mutationChain[i][2].foundation.damage}) then
            lackFoundation[i] = mutationChain[i][2].foundation.label
        end
        for _, condition in pairs({"dimension", "date", "lunar_phase", "time"}) do
            if mutationChain[i][2][condition] then
                if condition == "dimension" then
                    requiredDimension[i] = mutationChain[i][2][condition]
                elseif condition == "date" then
                    requiredDate[i] = mutationChain[i][2][condition]
                elseif condition == "lunar_phase" then
                    requiredLunarPhase[i] = mutationChain[i][2][condition]
                elseif condition == "time" then
                    requiredTime[i] = mutationChain[i][2][condition]
                end
            end
        end
        if requiredDimension[i] then
            lackFoundation[i] = nil
            lackEnvironmentConditions[i] = nil
        end
        if mutationChain[i][2].requiredMutatron then
            requiredMutatron[i] = true
        end
    end
    return lackFoundation, lackEnvironmentConditions, requiredDimension, requiredMutatron, requiredDate, requiredLunarPhase, requiredTime
end

function M.newBreedingTask(species)--新培育任务：优化已存在品种或培育新品种
    --1.先检查品种是否存在：若已存在则直接优化并结束
    if M.isSpeciesExisting(species) then
        M.optimizeExistingSpecies(species)
        return
    end
    --2.计算需要培育的品种和缺失的前置品种
    local mutationChain, lackSpecies = {}, {}
    M.calculateMutationChain(species, mutationChain, lackSpecies)
    --3.列出缺乏品种并终止
    if lackSpecies[1] then
        print("无法完成此突变任务，缺乏以下品种：")
        for _, species in ipairs(lackSpecies) do
            print("  - " .. species)
        end
        return
    end
    --4.校验每步突变条件（基石/环境/维度/日期/月相/时间/诱变机）
    print("校验突变条件")
    local lackFoundation, lackEnvironmentConditions, requiredDimension, requiredMutatron, requiredDate, requiredLunarPhase, requiredTime = M.checkMutationChain(mutationChain)
    --5.环境条件或诱变机不满足：列出并终止
    if next(lackEnvironmentConditions) or next(requiredMutatron) then
        if next(lackEnvironmentConditions) then
            print("无法完成此突变任务，以下突变不满足环境条件：")
        end
        for i, conditions in pairs(lackEnvironmentConditions) do
            for _, condition in pairs(conditions) do
                if condition == "temperature" then
                    if type(mutationChain[i][2].temperature) == "table" then
                        print(string.format("  - %s蜂突变仅在温度在%s到%s之间发生", mutationChain[i][2].name, mutationChain[i][2].temperature[1], mutationChain[i][2].temperature[2]))
                    else
                        print(string.format("  - %s蜂突变仅在温度为%s时发生", mutationChain[i][2].name, mutationChain[i][2].temperature))
                    end
                elseif condition == "humidity" then
                    print(string.format("  - %s蜂突变仅在湿度为%s时发生", mutationChain[i][2].name, mutationChain[i][2].humidity))
                elseif condition == "biome" then
                    print(string.format("  - %s蜂突变仅在%s生物群系中发生", mutationChain[i][2].name, mutationChain[i][2].biome))
                elseif condition == "biomeType" then
                    if mutationChain[i][2].biomeType == "ScummyBee" then
                        print("浮渣蜂突变仅在和[ocean, hot]或[ocean, wet]类似的生物群系中发生")
                    else
                        print(string.format("  - %s蜂突变仅在带有%s标签的生物群系中发生", mutationChain[i][2].name, mutationChain[i][2].biomeType))
                    end
                end
            end
        end
        if next(requiredMutatron) then
            print("以下突变仅支持通过诱变机进行：")
        end
        for i, _ in pairs(requiredMutatron) do
            print(string.format("  - %s蜂", mutationChain[i][2].name))
        end
        return
    end
    --6.处理缺失基石：提示补齐后重新检查
    while next(lackFoundation) do
        print("以下突变缺少基石：")
        for i, foundationName in pairs(lackFoundation) do
            print(string.format("  - %s蜂突变缺少：%s", mutationChain[i][2].name, foundationName))
        end
        io.write("是否重新检查？[Y/n]：")
        local answer = io.read()
        if answer ~= "Y" and answer ~= "y" then
            print("突变任务已取消")
            return
        else
            print("重新检查中")
            for i, _ in pairs(lackFoundation) do
                if bot.checkItem({name=mutationChain[i][2].foundation.name,damage=mutationChain[i][2].foundation.damage}) then
                    lackFoundation[i] = nil
                end
            end
        end
    end
    --7.确认人工干预条件（维度/日期/月相/时间）
    local function confirmContinue()
        io.write("是否继续执行突变？[Y/n]：")
        local answer = io.read()
        if answer == "Y" or answer == "y" then
            return false
        else
            print("突变任务已取消")
            return true
        end
    end
    local function confirm(conditionTable, conditionMessage, rangeMessage, sigleMessage)
        if next(conditionTable) then
            print(conditionMessage)
            for i, condition in pairs(conditionTable) do
                if type(condition) == "table" then
                    print(string.format(rangeMessage, mutationChain[i][2].name, condition[1], condition[2]))
                else
                    print(string.format(sigleMessage, mutationChain[i][2].name, condition))
                end
            end
            return confirmContinue()
        end
    end
    if confirm(requiredDimension, "以下突变需要在员工前往对应维度手动进行：", nil, "  - %s蜂突变需要维度 %s") then return end
    if confirm(requiredDate, "以下突变需要在对应日期进行：", "  - %s蜂突变仅在%s到%s之间发生", nil) then return end
    if confirm(requiredLunarPhase, "以下突变需要在对应月相进行：", "  - %s蜂突变需要月相在%s到%s之间", "  - %s蜂突变需要月相为%s") then return end
    if confirm(requiredTime, "以下突变需要在对应时间进行：", nil, "  - %s蜂突变仅在%s时发生") then return end
    print("突变条件核验完毕，开始执行突变")
    --8.执行：按突变链逐个培育新品种，将雄蜂/公主蜂存入ME网络，每步后充电
    for i = 1, #mutationChain do
        print(string.format("正在培育%s蜂", mutationChain[i][2].name))
        local droneSlot, princessSlot = M.newSpecies(mutationChain[i][1], mutationChain[i][2])
        robot.select(droneSlot--[[@as number]])
        upgrade_me.sendItems()
        robot.select(princessSlot--[[@as number]])
        upgrade_me.sendItems()
        bot.charge()
    end
    print("培育完毕！")
    device.destruct()
end

function M.initialize()--初始化至样板雄蜂体系（支持分阶段断点续跑）
    --已初始化：只需确认样板雄蜂池真实可用并补足；耗尽则轻量兜底，而非重跑人工公主仪式
    if beeData.initialized then
        if beeData.findTemplateDrone() then
            M.getAssistantDrones()--补足样板雄蜂数量至20以上（不足则繁殖到48）
            return
        end
        error("样板雄蜂池已物理耗尽，且ME网络与物品栏中不存在携带完整模板基因的纯合雄蜂。模板基因无法由非模板雄蜂重新培育，请放回至少一只纯模板雄蜂后重试。")
    end
    --未初始化：先验物理池。
    --·有记录且可获取（含岩石样板的仪式断点，或记录仍在）→ 交给下方分阶段流程续跑，绝不置位初始化；
    --·无记录却扫到"最终形态样板"（换机/data丢失，网络残留完成品）→ 采纳收尾。findTemplateDrone 会同步恢复速度基线。
    local hadRecord = beeData.getAssistantDroneTag() ~= nil
    if beeData.findTemplateDrone() then
        if hadRecord then
            --仪式断点（岩石样板在册）：续跑由分阶段流程处理
        else
            beeData.completeInitialization()--物理池已具备最终形态样板即视为初始化达成
            M.getAssistantDrones()--重建配对并补足
            return
        end
    end
    --1.检查初始化所需的基础品种是否齐备（凛冬蜂、岩石蜂）
    if not beeData.getDroneTag("forestry.speciesWintry") then
        error("初始化失败：缺乏基础品种凛冬蜂（forestry.speciesWintry）")
    end
    if not beeData.getDroneTag("extrabees.species.rock") then
        error("初始化失败：缺乏基础品种岩石蜂（extrabees.species.rock）")
    end
    local templateGenes = {
        [1] = {species = "forestry.speciesWintry",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "forestry.flowersSnow",territory = 1,effect = "forestry.effectGlacial",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = false,tolerantFlyer = false,caveDwelling = false},
        [2] = {species = "extrabees.species.rock",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectNone",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true},
        [3] = {species = "forestry.speciesWintry",speed = 2,lifespan = 3,fertility = 4,flowering = 1,flowerProvider = "extrabees.flower.rock",territory = 1,effect = "forestry.effectGlacial",temperatureTolerance = "BOTH_5",humidityTolerance = "BOTH_5",nocturnal = true,tolerantFlyer = true,caveDwelling = true}
    }
    local function hasGene(stack, chromosome, gene)
        return stack[chromosome][1] == gene or stack[chromosome][2] == gene
    end
    --判"纯合且逐染色体命中模板"
    local function matchesTemplate(stack, template)
        for _, chromosome in pairs(chromosomeList) do
            if stack[chromosome][1] ~= template[chromosome] or stack[chromosome][2] ~= template[chromosome] then
                return false
            end
        end
        return true
    end
    --按"纯合命中模板"在物品栏/ME网络查找现成蜜蜂tag（优先物品栏）
    local function findTemplateTag(name, template)
        for slot, stack in pairs(bot.inventory) do
            if slot ~= 0 and stack and stack.name == name and matchesTemplate(stack, template) then
                return stack.tag
            end
        end
        local stackList = upgrade_me.getItemsInNetwork({name = name})
        if not stackList then
            error("超出ME网络范围")
        end
        for _, stack in pairs(stackList) do
            if stack.name == name then
                local ok, genes = pcall(require("analyzeGenes"), stack)
                if ok and matchesTemplate(genes, template) then
                    return stack.tag
                end
            end
        end
        return nil
    end
    --按tag取回指定数量，返回槽位（取不到则nil）
    local function fetchTemplateSlot(name, template, count)
        local tag = findTemplateTag(name, template)
        if tag then
            return bot.checkItem({name = name, tag = tag}, count or 1)
        end
    end
    --宽松定位"凛冬且温湿全5"的公主作为基因种子（natural与否皆可续用，避免断点后重复索要始祖公主）
    local function findWintryTolerantTag()
        for slot, stack in pairs(bot.inventory) do
            if slot ~= 0 and stack and stack.type == "beePrincess" and hasGene(stack, "species", "forestry.speciesWintry") and hasGene(stack, "temperatureTolerance", "BOTH_5") and hasGene(stack, "humidityTolerance", "BOTH_5") then
                return stack.tag
            end
        end
        local stackList = upgrade_me.getItemsInNetwork({name = "Forestry:beePrincessGE"})
        if not stackList then
            error("超出ME网络范围")
        end
        for _, stack in pairs(stackList) do
            if stack.name == "Forestry:beePrincessGE" then
                local ok, genes = pcall(require("analyzeGenes"), stack)
                if ok and hasGene(genes, "species", "forestry.speciesWintry") and hasGene(genes, "temperatureTolerance", "BOTH_5") and hasGene(genes, "humidityTolerance", "BOTH_5") then
                    return stack.tag
                end
            end
        end
        return nil
    end

    local previousLabel = bot.inventoryLabel
    --初始化仪式阶段（beeData.initPhase）：0=未开始 1=模板1(凛冬)完成 2=模板2(岩石)完成 3=岩石样板已注册
    local phase = beeData.getInitPhase()
    --迁移兼容：旧版注册岩石样板时不写initPhase；"已注册(assistantDroneTag在册)且未初始化"一律视为阶段3
    if phase == 0 and beeData.getAssistantDroneTag() then
        phase = 3
        beeData.setInitPhase(3)
    end
    --续跑前校验：上一阶段产物必须真实可获取。模板1雄蜂+公主皆在→保留phase；否则退回0，
    --种子会复用现存的"凛冬全5公主"，不重新索要始祖公主
    if phase >= 1 and phase < 3 and not (fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[1], 1) and fetchTemplateSlot("Forestry:beePrincessGE", templateGenes[1], 1)) then
        phase = 0
        beeData.setInitPhase(0)
    end
    --模板2(岩石)雄蜂丢失则退回阶段1（仅注册前的中间阶段需要；注册后模板1/2只是普通亲本，缺了不影响培育田野）
    if phase >= 2 and phase < 3 and not fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[2], 1) then
        phase = 1
        beeData.setInitPhase(1)
    end
    local princessSlot, drone1Slot, drone2Slot, princess2Slot
    --阶段1：产出"温湿全5"凛冬（模板1）的纯合雄蜂与公主
    if phase < 1 then
        print("正在提纯温度适应性全5、湿度适应性全5基因")
        local seedSlot = fetchTemplateSlot("Forestry:beePrincessGE", templateGenes[1], 1)
        if not seedSlot then
            local seedTag = findWintryTolerantTag()
            if seedTag then
                seedSlot = bot.checkItem({name = "Forestry:beePrincessGE", tag = seedTag}, 1)
            end
        end
        if not seedSlot then
            --首次运行：向用户索要适应性全5的始祖凛冬公主
            print("请提供一只使用适应性调整器将温度适应性、湿度适应性均调整到全5的始祖种凛冬公主")
            bot.inventoryLabel = "initialize:getingTorlance5Princess"
            while true do
                os.sleep(1)
                for _, slot in pairs(bot.getItemsWithLabel(bot.inventoryLabel)) do
                    if bot.inventory[slot].type == "beePrincess" and bot.inventory[slot].isNatural == true and hasGene(bot.inventory[slot], "species", "forestry.speciesWintry") and hasGene(bot.inventory[slot], "temperatureTolerance", "BOTH_5") and hasGene(bot.inventory[slot], "humidityTolerance", "BOTH_5") then
                        seedSlot = slot
                        break
                    else
                        robot.select(slot)
                        upgrade_me.sendItems()
                    end
                end
                if seedSlot then
                    break
                end
            end
            bot.inventoryLabel = previousLabel
            bot.inventory[seedSlot].inventoryLabel = previousLabel
        end
        --开头已检查凛冬蜂存在，此处直接获取其纯合亲本雄蜂
        local wintryDroneSlot = doUntil(function()
            return bot.checkItem({name="Forestry:beeDroneGE",tag=beeData.getDroneTag("forestry.speciesWintry")}, 16)
        end)
        drone1Slot, princessSlot = M.purify(seedSlot, wintryDroneSlot, templateGenes[1], wintryDroneSlot, ":initializing1")
        if not drone1Slot then
            error("初始化失败：阶段1提纯凛冬蜂失败")
        end
        if bot.inventory[wintryDroneSlot] and wintryDroneSlot ~= drone1Slot then
            robot.select(wintryDroneSlot)
            upgrade_me.sendItems()
        end
        beeData.setInitPhase(1)
        phase = 1
    end
    --阶段2：向凛冬公主引入"岩石种"，产出纯合岩石（模板2）雄蜂与岩石公主
    if phase < 2 then
        print("正在向石头蜂引入生育4x、温度适应性全5、湿度适应性全5基因")
        princessSlot = princessSlot or fetchTemplateSlot("Forestry:beePrincessGE", templateGenes[1], 1)
        drone1Slot = drone1Slot or fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[1], 16)
        if not princessSlot or not drone1Slot then
            error("初始化失败：阶段2缺少凛冬模板材料，请重新执行初始化")
        end
        --开头已检查岩石蜂存在，此处直接获取其纯合亲本雄蜂
        local drone2Parent = doUntil(function()
            return bot.checkItem({name="Forestry:beeDroneGE",tag=beeData.getDroneTag("extrabees.species.rock")}, 1)
        end)
        drone2Slot, princessSlot = M.purify(princessSlot, drone2Parent, templateGenes[2], drone1Slot, ":initializing2")
        if not drone2Slot then
            error("初始化失败：阶段2提纯岩石蜂失败")
        end
        beeData.setInitPhase(2)
        phase = 2
    end
    --阶段3：用自然公主制得"同性状凛冬蜂"（模板3），并注册岩石样板雄蜂+配对公主
    if phase < 3 then
        drone2Slot = drone2Slot or fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[2], 16)
        princessSlot = princessSlot or fetchTemplateSlot("Forestry:beePrincessGE", templateGenes[2], 1)
        if not drone2Slot or not princessSlot then
            error("初始化失败：阶段3缺少岩石模板材料，请重新执行初始化")
        end
        --若模板3（凛冬石花）雄蜂已存在，说明此前已提纯过C，跳过重复操作（覆盖"已提纯但未及标记阶段"的崩溃窗口）
        local wintryRockDrone = fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[3], 1)
        if wintryRockDrone then
            drone1Slot = wintryRockDrone
        else
            drone1Slot = drone1Slot or fetchTemplateSlot("Forestry:beeDroneGE", templateGenes[1], 16)
            if not drone1Slot then
                error("初始化失败：阶段3缺少凛冬模板雄蜂，请重新执行初始化")
            end
            princess2Slot = bot.checkItem({name = "Forestry:beePrincessGE", tag = beeData.getPrincessTag(true)}, 1)
            if not princess2Slot then
                error("初始化失败：ME网络内缺少初始公主蜂")
            end
            print("正在向凛冬蜂引入采蜜对象石头、夜行性、耐雨飞行性、穴居性基因")
            robot.select(drone1Slot--[[@as number]])
            robot.dropUp(robot.count(drone1Slot--[[@as number]]) - 1)
            drone1Slot, princess2Slot = M.purify(princess2Slot, drone1Slot, templateGenes[3], drone2Slot, ":initializing3")
        end
        --注册岩石样板（speedLevel、assistantDroneTag），配对公主为岩石公主（幂等，可重复执行）
        beeData.updateAssistantDrone(drone2Slot, true)
        beeData.updateAssistantPrincess(princessSlot)
        if princess2Slot then
            beeData.updateUsingPrincess(princess2Slot)
        end
        for _, slot in pairs({drone1Slot, princess2Slot, drone2Slot, princessSlot}) do
            if slot then
                robot.select(slot--[[@as number]])
                upgrade_me.sendItems()
            end
        end
        drone1Slot, princess2Slot, drone2Slot, princessSlot = nil, nil, nil, nil
        beeData.setInitPhase(3)
        phase = 3
    end
    --2.培育寻常蜂（若尚不存在）
    if not beeData.getDroneTag("forestry.speciesCommon") then
        print("正在培育寻常蜂")
        local tempDrone, tempPrincess = M.newSpecies("forestry.speciesCommon", {name="寻常",parents={"forestry.speciesWintry","extrabees.species.rock"},baseChance=15.0})
        if tempDrone then
            robot.select(tempDrone)
            upgrade_me.sendItems()
            robot.select(tempPrincess)
            upgrade_me.sendItems()
        else
            error("初始化失败：培育寻常蜂失败")
        end
    end
    --3.培育田野蜂（最终形态样板；updateAssistantDrone 采纳时将初始化置位）
    if not beeData.initialized then
        print("正在培育田野蜂")
        local tempDrone, tempPrincess = M.newSpecies("forestry.speciesCultivated", {name="田野",parents={"forestry.speciesCommon","extrabees.species.rock"},baseChance=12.0})
        if tempDrone then
            robot.select(tempDrone)
            upgrade_me.sendItems()
            robot.select(tempPrincess)
            upgrade_me.sendItems()
        else
            error("初始化失败：培育田野蜂失败")
        end
    end
    bot.inventoryLabel = previousLabel
    beeData.completeInitialization()--兜底置位并落盘
end

return M
