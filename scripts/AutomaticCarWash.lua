--[[
Copyright (C) Achimobil 2023-2024

Author: Achimobil
Date: 07.04.2023
Version: 1.1.0.0

Contact:
https://www.achimobil.de

History:
V 1.0.0.0 @ 29.04.2022 - Release Version.
V 1.0.1.0 @ 09.05.2022 - Fix for reconfigurating vehicle while script is running
V 1.1.0.0 @ 07.04.2023 - dirt/dagame/wear steps over xml changable
V 2.0.0.0 @ 16.11.2024 - Convert for LS25

Important:
Free for use in other mods - no permission needed, only provide my name.
No changes are to be made to this script without permission from Achimobil.

Frei verwendbar - keine erlaubnis nötig, Namensnennung im Mod erforderlich.
An diesem Skript dürfen ohne Genehmigung von Achimobil keine Änderungen vorgenommen werden.
]]

AutomaticCarWash = {};
AutomaticCarWash.Debug = false;

function AutomaticCarWash.DebugTable(text, myTable, maxDepth)
	if not AutomaticCarWash.Debug then return end
	if myTable == nil then
		Logging.info("AutomaticCarWashDebug: " .. text .. " is nil");
	else
		Logging.info("AutomaticCarWashDebug: " .. text)
		DebugUtil.printTableRecursively(myTable,"_",0, maxDepth or 2);
	end
end

-- Beispiel: AutomaticCarWash.DebugText("Alter: %s", age)
function AutomaticCarWash.DebugText(text, ...)
	if not AutomaticCarWash.Debug then return end
	Logging.info("AutomaticCarWashDebug: " .. string.format(text, ...));
end

function AutomaticCarWash.prerequisitesPresent(specializations)
    return true
end

function AutomaticCarWash.initSpecialization()
	AutomaticCarWash.DebugText("initSpecialization")
    local schema = Placeable.xmlSchema
    schema:setXMLSpecializationType("AutomaticCarWash")
    
    local baseXmlPath = "placeable.automaticCarWash"
    
    schema:register(XMLValueType.NODE_INDEX, baseXmlPath .. "#triggerNode", "Trigger node for automatic")
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#dirtAmount", "dirt change per interval", -0.1)
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#damageAmount", "damage change per interval", -0,05)
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#wearAmount", "wear change per interval", -0,02)

    schema:setXMLSpecializationType()
end

function AutomaticCarWash.registerFunctions(placeableType)
    SpecializationUtil.registerFunction(placeableType, "onTriggerCallback", AutomaticCarWash.onTriggerCallback)
    SpecializationUtil.registerFunction(placeableType, "CleanCar", AutomaticCarWash.CleanCar)
    SpecializationUtil.registerFunction(placeableType, "CleanOneVehicle", AutomaticCarWash.CleanOneVehicle)
end

function AutomaticCarWash.registerEventListeners(placeableType)
    SpecializationUtil.registerEventListener(placeableType, "onLoad", AutomaticCarWash)
    SpecializationUtil.registerEventListener(placeableType, "onFinalizePlacement", AutomaticCarWash)
    SpecializationUtil.registerEventListener(placeableType, "onDelete", AutomaticCarWash)
end

function AutomaticCarWash:onLoad(savegame)
    local baseXmlPath = "placeable.automaticCarWash"
            
    -- hier für server und client
    self.spec_automaticCarWash = {}
    local spec = self.spec_automaticCarWash
    spec.available = false;
    spec.vehicleInTrigger = {};
    spec.activated = false;
    
    spec.triggerNode = self.xmlFile:getValue(baseXmlPath.."#triggerNode", nil, self.components, self.i3dMappings);
	spec.dirtAmount = self.xmlFile:getValue(baseXmlPath .. "#dirtAmount", -0.1)
	spec.damageAmount = self.xmlFile:getValue(baseXmlPath .. "#damageAmount", -0.05)
	spec.wearAmount = self.xmlFile:getValue(baseXmlPath .. "#wearAmount", -0.02)
    
    spec.initialized = true;
	
	AutomaticCarWash.DebugTable("onLoad", spec)
end

function AutomaticCarWash:onFinalizePlacement()
    local spec = self.spec_automaticCarWash;
    
    if self.isServer then
        if spec.triggerNode ~= nil then
            addTrigger(spec.triggerNode, "onTriggerCallback", self);
        else
            Logging.Error("Triggernode missing");
        end
    end
end

function AutomaticCarWash:onDelete()
    local spec = self.spec_automaticCarWash;
    
    if self.isServer then
        if spec.triggerNode ~= nil then
            removeTrigger(spec.triggerNode)
        end
    end
end

function AutomaticCarWash:onTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
	AutomaticCarWash.DebugText("CleanOneVehicle(%s, %s, %s, %s, %s)", triggerId, otherId, onEnter, onLeave, onStay)
    
    local spec = self.spec_automaticCarWash;
    local vehicle = g_currentMission:getNodeObject(otherId);
    if vehicle ~= nil then
        if onEnter then
            local foundInTable = false;
            for i=0, table.getn(spec.vehicleInTrigger) do
                if spec.vehicleInTrigger[i] ~= nil and spec.vehicleInTrigger[i] == otherId then
                    foundInTable = true;
                end
            end
            if not foundInTable then
                table.insert(spec.vehicleInTrigger,otherId);
                if spec.timerId == nil then
                    self:CleanCar();
                else
                    self:CleanOneVehicle(vehicle);
                end
            end
        end
        if onLeave then
            for i=0, table.getn(spec.vehicleInTrigger) do
                if spec.vehicleInTrigger[i] ~= nil and spec.vehicleInTrigger[i] == otherId then
                    table.remove(spec.vehicleInTrigger, i);
                end
            end
        end
    end
end

function AutomaticCarWash:CleanOneVehicle(vehicle)
	AutomaticCarWash.DebugText("CleanOneVehicle(%s)", vehicle)
	local spec = self.spec_automaticCarWash
	
    local actionDone = false;
    if vehicle == nil then
        return false;
    end
    
    if vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() >= 0.0001 and spec.dirtAmount ~= 0 then
        -- set amount of wash per interval here. It is in percentage where 1 is 100%
        vehicle:cleanVehicle(spec.dirtAmount * -1);
        actionDone = true;
    end
    
    -- uncomment complete if when no repear should be done
    if vehicle.getDamageAmount ~= nil and vehicle:getDamageAmount() >= 0.0001 and spec.damageAmount ~= 0 then
        -- set amount of repair per interval here. It is in percentage where 1 is 100%
        vehicle:addDamageAmount(spec.damageAmount, true);
        actionDone = true;
    end
    
    -- uncomment complete if when no painting should be done
    if vehicle.getWearTotalAmount ~= nil and vehicle:getWearTotalAmount() >= 0.0001 and spec.wearAmount ~= 0 then
        -- set amount of painting per interval here. It is in percentage where 1 is 100%
        vehicle:addWearAmount(spec.wearAmount, true);
        actionDone = true;
    end
    
    return actionDone;
end

function AutomaticCarWash:CleanCar()
	AutomaticCarWash.DebugText("CleanCar()")
    local spec = self.spec_automaticCarWash
    if table.getn(spec.vehicleInTrigger) > 0 then

        local actionDone = false;
    
        for _,vehicle in pairs(spec.vehicleInTrigger) do
            local vehicle = g_currentMission.nodeToObject[vehicle];
            
            AutomaticCarWash.DebugText("getDirtAmount: " .. vehicle:getDirtAmount());
            AutomaticCarWash.DebugText("getDamageAmount: " .. vehicle:getDamageAmount());
            AutomaticCarWash.DebugText("getWearTotalAmount: " .. vehicle:getWearTotalAmount());
            if vehicle ~= nil then
                local hasDoneSomething = self:CleanOneVehicle(vehicle);
                
                if hasDoneSomething == true then
                    actionDone = true;
                end
            end
        end;

        if not actionDone then
            -- clean, remove timer
            spec.timerId = nil;
        else
            -- not clean, use timer
            if spec.timerId ~= nil then
                return true;
            else
                -- set intervall length here in miliseconds
                spec.timerId = addTimer(5000, "CleanCar", self);
            end        
        end
    else
        -- no vehicle, remove timer
        spec.timerId = nil;
    end
end