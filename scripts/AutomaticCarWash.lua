--[[
Copyright (C) Achimobil 2023-2025

Author: Achimobil
Date: 17.02.2025
Version: 2.0.2.1

Contact: https://github.com/Achimobil/FS25_StaffedWorkshop

History:
V 1.0.0.0 @ 29.04.2022 - Release Version.
V 1.0.1.0 @ 09.05.2022 - Fix for reconfigurating vehicle while script is running
V 1.1.0.0 @ 07.04.2023 - dirt/dagame/wear steps over xml changable
V 2.0.0.0 @ 16.11.2024 - Convert for LS25
V 2.0.1.0 @ 13.02.2025 - Cleanup and fix some reported lua errors
                         timerLength added for XML
                         Add drying after washing
V 2.0.2.0 @ 15.02.2025 - No Action when Vehicle is in movement
V 2.0.2.1 @ 17.02.2025 - Special case for hard attached implements added

Important:
Free for use in other mods - no permission needed, only provide my name.
No changes are to be made to this script without permission from Achimobil.

Frei verwendbar - keine erlaubnis nötig, Namensnennung im Mod erforderlich.
An diesem Skript dürfen ohne Genehmigung von Achimobil keine Änderungen vorgenommen werden.
]]

AutomaticCarWash = {};
AutomaticCarWash.Debug = true;

--- Print the given Table to the log
-- @param string text parameter Text before the table
-- @param table myTable The table to print
-- @param number maxDepth depth of print, default 2
function AutomaticCarWash.DebugTable(text, myTable, maxDepth)
    if not AutomaticCarWash.Debug then return end
    if myTable == nil then
        Logging.info("AutomaticCarWashDebug: " .. text .. " is nil");
    else
        Logging.info("AutomaticCarWashDebug: " .. text)
        DebugUtil.printTableRecursively(myTable,"_",0, maxDepth or 2);
    end
end

---Print the text to the log. Example: AutomaticCarWash.DebugText("Alter: %s", age)
-- @param string text the text to print formated
-- @param any ... format parameter
function AutomaticCarWash.DebugText(text, ...)
    if not AutomaticCarWash.Debug then return end
    Logging.info("AutomaticCarWashDebug: " .. string.format(text, ...));
end

function AutomaticCarWash.prerequisitesPresent(specializations)
    return true
end

---
function AutomaticCarWash.initSpecialization()
    AutomaticCarWash.DebugText("initSpecialization")
    local schema = Placeable.xmlSchema
    schema:setXMLSpecializationType("AutomaticCarWash")

    local baseXmlPath = "placeable.automaticCarWash"

    schema:register(XMLValueType.NODE_INDEX, baseXmlPath .. "#triggerNode", "Trigger node for automatic")
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#dirtAmount", "dirt change per interval", -0.1)
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#damageAmount", "damage change per interval", -0,05)
    schema:register(XMLValueType.FLOAT, baseXmlPath .. "#wearAmount", "wear change per interval", -0,02)
    schema:register(XMLValueType.INT, baseXmlPath .. "#timerLength", "time for timer (miliseconds", 3000)

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

---Called on loading
-- @param table savegame savegame
function AutomaticCarWash:onLoad(savegame)
    local baseXmlPath = "placeable.automaticCarWash"

    -- hier für server und client
    self.spec_automaticCarWash = {}
    local spec = self.spec_automaticCarWash
    spec.available = false;
    spec.vehiclesInTrigger = {};
    spec.activated = false;

    spec.triggerNode = self.xmlFile:getValue(baseXmlPath.."#triggerNode", nil, self.components, self.i3dMappings);
    spec.dirtAmount = self.xmlFile:getValue(baseXmlPath .. "#dirtAmount", -0.1)
    spec.damageAmount = self.xmlFile:getValue(baseXmlPath .. "#damageAmount", -0.05)
    spec.wearAmount = self.xmlFile:getValue(baseXmlPath .. "#wearAmount", -0.02)
    spec.timerLength = self.xmlFile:getValue(baseXmlPath .. "#timerLength", 3000)

    spec.initialized = true;

    AutomaticCarWash.DebugTable("onLoad", spec)
end

---
function AutomaticCarWash:onFinalizePlacement()
    local spec = self.spec_automaticCarWash;

    if self.isServer then
        if spec.triggerNode ~= nil then
            addTrigger(spec.triggerNode, "onTriggerCallback", self);
        else
            Logging.error("Triggernode missing");
        end
    end
end

---
function AutomaticCarWash:onDelete()
    local spec = self.spec_automaticCarWash;

    if self.isServer then
        if spec.triggerNode ~= nil then
            removeTrigger(spec.triggerNode)
        end
    end
end

---Callback when trigger changes state
-- @param integer triggerId
-- @param integer otherId
-- @param boolean onEnter
-- @param boolean onLeave
-- @param boolean onStay
function AutomaticCarWash:onTriggerCallback(triggerId, otherId, onEnter, onLeave, onStay)
    AutomaticCarWash.DebugText("onTriggerCallback(%s, %s, %s, %s, %s)", triggerId, otherId, onEnter, onLeave, onStay)

    local spec = self.spec_automaticCarWash;
    local vehicle = g_currentMission:getNodeObject(otherId);
    if vehicle ~= nil and vehicle.rootNode ~= nil then
--         AutomaticCarWash.DebugTable("vehicle", vehicle);
        if onEnter then
            local foundInTable = false;

            for _,vehicleInTrigger in pairs(spec.vehiclesInTrigger) do
                if vehicleInTrigger == vehicle.rootNode then
                    foundInTable = true;
                end
            end
            if not foundInTable then
                table.insert(spec.vehiclesInTrigger, vehicle.rootNode);
                AutomaticCarWash.DebugText("Added rootNode: %s)", vehicle.rootNode);
                if spec.timerId == nil then
                    self:CleanCar();
                else
                    self:CleanOneVehicle(vehicle);
                end
            end

            -- search for hard attached
            local attacherJointSpec = vehicle.spec_attacherJoints
            if attacherJointSpec ~= nil then
                for _, attachedImplement in pairs(attacherJointSpec.attachedImplements) do
    --                 AutomaticCarWash.DebugTable("attachedImplement", attachedImplement);
                    if attachedImplement.object.spec_attachable.isHardAttached then

                        local foundAttachedInTable = false;

                        for _,vehicleInTrigger in pairs(spec.vehiclesInTrigger) do
                            if vehicleInTrigger == attachedImplement.object.rootNode then
                                foundAttachedInTable = true;
                            end
                        end
                        if not foundAttachedInTable then
                            table.insert(spec.vehiclesInTrigger, attachedImplement.object.rootNode);
                            AutomaticCarWash.DebugText("Added hard attached rootNode: %s)", attachedImplement.object.rootNode);
                            if spec.timerId == nil then
                                self:CleanCar();
                            else
                                self:CleanOneVehicle(attachedImplement.object);
                            end
                        end

                    end
                end
            end

        end
        if onLeave then
            for i = #spec.vehiclesInTrigger, 1, -1 do
                local vehicleInTrigger = spec.vehiclesInTrigger[i];
                if vehicleInTrigger ~= nil and vehicleInTrigger == vehicle.rootNode then
                    table.remove(spec.vehiclesInTrigger, i);
                    AutomaticCarWash.DebugText("Removed rootNode: %s)", vehicle.rootNode);
                end
            end

            -- search for hard attached
            local attacherJointSpec = vehicle.spec_attacherJoints
            if attacherJointSpec ~= nil then
                for _, attachedImplement in pairs(attacherJointSpec.attachedImplements) do
    --                 AutomaticCarWash.DebugTable("attachedImplement", attachedImplement);
                    if attachedImplement.object.spec_attachable.isHardAttached then

                        for i = #spec.vehiclesInTrigger, 1, -1 do
                            local vehicleInTrigger = spec.vehiclesInTrigger[i];
                            if vehicleInTrigger ~= nil and vehicleInTrigger == attachedImplement.object.rootNode then
                                table.remove(spec.vehiclesInTrigger, i);
                                AutomaticCarWash.DebugText("Removed hard attached rootNode: %s)", attachedImplement.object.rootNode);
                            end
                        end

                    end
                end
            end
        end
    end
end

---Clean the given vehicle
-- @param Vehicle vehicle the vehicle to clean
-- @return boolean something processed
function AutomaticCarWash:CleanOneVehicle(vehicle)
    AutomaticCarWash.DebugText("CleanOneVehicle(%s)", vehicle)
    local spec = self.spec_automaticCarWash

    local actionDone = false;
    if vehicle == nil then
        return false;
    end


    -- timer soll weiter laufen wenn sich das fahzeug bewegt, aber keine Aktion durchgeführt werden
    local lastSpeed = 0;
    if vehicle.getLastSpeed ~= nil then
        lastSpeed = vehicle:getLastSpeed(true) + vehicle:getLastSpeed();
    end
        AutomaticCarWash.DebugText("lastSpeed: " .. tostring(lastSpeed));
    if lastSpeed < 5 then
        -- Fahrzeug leicht anheben, damit es bei beweglichen triggern auch wieder runter fährt
        local x, y, z = getTranslation(vehicle.rootNode);
        setTranslation(vehicle.rootNode, x, y+0.000001, z);
    end
    if lastSpeed > 1 then
        return true;
    end

    if vehicle.getDirtAmount ~= nil and vehicle:getDirtAmount() >= 0.0001 and spec.dirtAmount ~= 0 then
        -- set amount of wash per interval here. It is in percentage where 1 is 100%
        vehicle:cleanVehicle(spec.dirtAmount * -1);
        AutomaticCarWash.DebugText("cleanVehicle(%s)", spec.dirtAmount * -1)
        actionDone = true;
    elseif vehicle.getIsWet ~= nil and vehicle:getIsWet() and vehicle.addWetnessAmount ~= nil then
        -- when not dirt anymore, dry with double wash speed with next timer run until dry
        vehicle:addWetnessAmount(spec.dirtAmount * 2);
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

--- Method called by the timer. Removes Timer when nothing has be done or start one when there is no timer
-- @return boolean timerResult true when timer should be called again
function AutomaticCarWash:CleanCar()
    AutomaticCarWash.DebugText("CleanCar()")
    local spec = self.spec_automaticCarWash
    if #spec.vehiclesInTrigger > 0 then

        local actionDone = false;

        for _,vehicleInTrigger in pairs(spec.vehiclesInTrigger) do
            local vehicle = g_currentMission.nodeToObject[vehicleInTrigger];

            if vehicle ~= nil then
                if vehicle.getName ~= nil then
                    AutomaticCarWash.DebugText("getName: " .. vehicle:getName());
                end
                if vehicle.getDirtAmount ~= nil then
                    AutomaticCarWash.DebugText("getDirtAmount: " .. vehicle:getDirtAmount());
                end
                if vehicle.getDamageAmount ~= nil then
                    AutomaticCarWash.DebugText("getDamageAmount: " .. vehicle:getDamageAmount());
                end
                if vehicle.getWearTotalAmount ~= nil then
                    AutomaticCarWash.DebugText("getWearTotalAmount: " .. vehicle:getWearTotalAmount());
                end
                if vehicle.getIsWet ~= nil then
                    AutomaticCarWash.DebugText("getIsWet: " .. tostring(vehicle:getIsWet()));
                end

                local hasDoneSomething = self:CleanOneVehicle(vehicle);

                if hasDoneSomething == true then
                    actionDone = true;
                end
            end
        end;

        -- trigger not empty
        if spec.timerId ~= nil then
            -- return true so existing trigger runs again
            AutomaticCarWash.DebugText("restart timer");
            return true;
        else
            -- set intervall length here in miliseconds
            AutomaticCarWash.DebugText("create timer");
            spec.timerId = addTimer(spec.timerLength, "CleanCar", self);
            return;
        end
    else
        -- no vehicle, remove timer
        AutomaticCarWash.DebugText("remove timer");
        spec.timerId = nil;
    end

    return;
end