local mp_pointing = false
local keyPressed = false
local once = true
local oldval = false
local oldvalped = false

local function RotAnglesToDirection(rotation)
    local adjustedRotation = vector3(math.rad(rotation.x), math.rad(rotation.y), math.rad(rotation.z))
    local direction = vector3(
        -math.sin(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.cos(adjustedRotation.z) * math.abs(math.cos(adjustedRotation.x)),
        math.sin(adjustedRotation.x)
    )
    return direction
end

local function getCoordsFromCam() 
    local playerPed = PlayerPedId()
    
    local camCoords = GetGameplayCamCoord()
    
    local camRot = GetGameplayCamRot(2)
    local camDirection = RotAnglesToDirection(camRot)
    
    local entityForward = GetEntityForwardVector(playerPed)
    local dotProduct = (entityForward.x * camDirection.x) + (entityForward.y * camDirection.y) + (entityForward.z * camDirection.z)
    
    if dotProduct < 0.0 then
        local projectionX = camDirection.x - (entityForward.x * dotProduct)
        local projectionY = camDirection.y - (entityForward.y * dotProduct)
        local projectionZ = camDirection.z - (entityForward.z * dotProduct)

        local lenSq = (projectionX * projectionX) + (projectionY * projectionY) + (projectionZ * projectionZ)
        if lenSq < 0.0001 then
            return nil
        else
            local len = math.sqrt(lenSq)
            camDirection = vector3(projectionX / len, projectionY / len, projectionZ / len)
        end
    end
    
    local distance = 1000.0
    local destination = camCoords + (camDirection * distance)

    local rayHandle = StartShapeTestRay(camCoords.x, camCoords.y, camCoords.z, destination.x, destination.y, destination.z, 10, playerPed, 7)
    local _, hit, endCoords, surfaceNormal, materialHash = GetShapeTestResult(rayHandle)

    if hit == 1 then
        return endCoords
    else

        return destination
    end
end

local function startPointing()
    local ped = PlayerPedId()
    RequestAnimDict("ai_react@point@base")
    while not HasAnimDictLoaded("ai_react@point@base") do
        Wait(0)
    end
    SetPedCurrentWeaponVisible(ped, 0, 1, 1, 1)
    SetPedConfigFlag(ped, 36, 1)
	TaskPlayAnim( ped,"ai_react@point@base","point_fwd", -1, -1, -1, 30, 0, false, false, false)
    RemoveAnimDict("ai_react@point@base")
end

local function stopPointing()
    local ped = PlayerPedId()
    RequestTaskMoveNetworkStateTransition(ped, "Stop")
    if not IsPedInjured(ped) then
        ClearPedSecondaryTask(ped)
    end
    if not IsPedInAnyVehicle(ped, 1) then
        SetPedCurrentWeaponVisible(ped, 1, 1, 1, 1)
    end
    SetPedConfigFlag(ped, 36, 0)
    ClearPedSecondaryTask(PlayerPedId())
end

local pointingPlayers = {}
local lastSyncTime = 0
local lastSyncCoords = vector3(0,0,0)

Citizen.CreateThread(function()
    while true do
        Wait(0)
        local ped = PlayerPedId()
        
        for playerId, pCoords in pairs(pointingPlayers) do
            local playerIdx = GetPlayerFromServerId(playerId)
            if playerIdx ~= -1 and playerIdx ~= PlayerId() then
                local otherPed = GetPlayerPed(playerIdx)
                if DoesEntityExist(otherPed) then
                    if not IsEntityPlayingAnim(otherPed, "ai_react@point@base", "point_fwd", 1) then
                        RequestAnimDict("ai_react@point@base")
                        while not HasAnimDictLoaded("ai_react@point@base") do Wait(0) end
                        TaskPlayAnim(otherPed, "ai_react@point@base", "point_fwd", -1, -1, -1, 30, 0, false, false, false)
                    end
                    SetIkTarget(otherPed, 4, 0, 0, pCoords.x, pCoords.y, pCoords.z, 0, 0, 0)
                    RequestTaskMoveNetworkStateTransition(otherPed, "Stop")
                end
            end
        end

		local coords = getCoordsFromCam()
        if once then
            once = false
        end
        if not keyPressed then
            if IsControlPressed(0, 0x4CC0E2FE) and not mp_pointing and IsPedOnFoot(ped) then
                Wait(200)
                if not IsControlPressed(0, 0x4CC0E2FE) then
                    keyPressed = true
                    startPointing()
                    mp_pointing = true
                    if coords then
                        TriggerServerEvent('pointing:update', true, coords)
                        lastSyncCoords = coords
                        lastSyncTime = GetGameTimer()
                    end
                else
                    keyPressed = true
                    while IsControlPressed(0, 0x4CC0E2FE) do
                        Wait(50)
                    end
                end
            elseif (IsControlPressed(0, 0x4CC0E2FE) and mp_pointing) or (not IsPedOnFoot(ped) and mp_pointing) then
                keyPressed = true
                mp_pointing = false
                stopPointing()
                TriggerServerEvent('pointing:update', false, vector3(0,0,0))
            end
        end
        if keyPressed then
            if not IsControlPressed(0, 0x4CC0E2FE) then
                keyPressed = false
            end
        end

        if IsEntityPlayingAnim(ped,"ai_react@point@base","point_fwd",1) then
            if not mp_pointing then
                stopPointing()
                TriggerServerEvent('pointing:update', false, vector3(0,0,0))
            elseif not IsPedOnFoot(ped) then
                stopPointing()
                mp_pointing = false
                TriggerServerEvent('pointing:update', false, vector3(0,0,0))
            elseif coords then  
                SetIkTarget(ped, 4, 0, 0, coords.x, coords.y, coords.z, 0, 0, 0)
                RequestTaskMoveNetworkStateTransition(ped, "Stop")
                
                local currentTime = GetGameTimer()
                if currentTime - lastSyncTime > 150 then
                    if #(coords - lastSyncCoords) > 0.5 then
                        TriggerServerEvent('pointing:update', true, coords)
                        lastSyncCoords = coords
                        lastSyncTime = currentTime
                    end
                end
            end
        end
    end
end)

RegisterNetEvent('pointing:sync')
AddEventHandler('pointing:sync', function(playerId, isPointing, pos, rot)
    if isPointing then
        pointingPlayers[playerId] = pos
    else
        pointingPlayers[playerId] = nil
        local playerIdx = GetPlayerFromServerId(playerId)
        if playerIdx ~= -1 and playerIdx ~= PlayerId() then
            local otherPed = GetPlayerPed(playerIdx)
            if DoesEntityExist(otherPed) then
                ClearPedTasks(otherPed)
            end
        end
    end
end)

