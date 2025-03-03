--[[

 * Copyright (C) Rotorflight Project
 *
 *
 * License GPLv3: https://www.gnu.org/licenses/gpl-3.0.en.html
 *
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License version 3 as
 * published by the Free Software Foundation.
 *
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 
 * Note.  Some icons have been sourced from https://www.flaticon.com/
 * 

]] --
local arg = {...}
local config = arg[1]

local telemetry = {}
local sensors = {}
local protocol, telemetrySOURCE, crsfSOURCE
local sensorRateLimit = os.clock()
local SENSOR_RATE = 0.25 -- rate in seconds

-- Store the last validated sensors and timestamp
local lastValidationResult = nil
local lastValidationTime = 0
local VALIDATION_RATE_LIMIT = 2 -- Rate limit in seconds

local lastCacheFlushTime = 0
local CACHE_FLUSH_INTERVAL = 10 -- Flush cache every 10 seconds

local telemetryState = false

-- Predefined sensor mappings
local sensorTable = {
    -- RSSI Sensors
    rssi = {
        name = "RSSI",
        mandatory = true,
        sport = {
            {appId=0xF101, subId=0},
            "RSSI",   -- fallback for older versions (should never get here if running ethos 1.6.2 or newer)
        },
        crsf = {
            {crsfId=0x14, subIdStart=0, subIdEnd=1},
            "Rx RSSI1", -- fallback for older versions (should never get here if running ethos 1.6.2 or newer)
        },
        crsfLegacy = {
            {crsfId=0x14, subIdStart=0, subIdEnd=1},
            "RSSI 1",   -- fallback for older versions (should never get here if running ethos 1.6.2 or newer)
            "RSSI 2",
            "Rx Quality",
        }
    },

    -- Arm Flags
    armflags = {
        name = "Arming Flags",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5122},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5462}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1202}
        },
        crsfLegacy = {nil}
    },

    -- Voltage Sensors
    voltage = {
        name = "Voltage",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0210},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0211},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0218},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x021A},
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1011},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1041},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1051},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1080},
        },
        crsfLegacy = {"Rx Batt"}
    },

    -- RPM Sensors
    rpm = {
        name = "Head Speed",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0500}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10C0}
        },
        crsfLegacy = {"GPS Alt"}
    },

    -- Current Sensors
    current = {
        name = "Current",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0200},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0201}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1012},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1042}
        },
        crsfLegacy = {"Rx Curr"}
    },

    -- Temperature Sensors
    tempESC = {
        name = "ESC Temperature",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0B70}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10A0}
        },
        crsfLegacy = {"GPS Speed"}
    },
    tempMCU = {
        name = "MCU Temperature",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0400, mspgt = 12.08},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0401, msplt = 12.07}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x10A3}
        },
        crsfLegacy = {"GPS Sats"}
    },

    -- Fuel and Capacity Sensors
    fuel = {
        name = "Charge Level",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x0600}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1014}
        },
        crsfLegacy = {"Rx Batt%"}
    },
    capacity = {
        name = "Consumption",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5250}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1013}
        },
        crsfLegacy = {"Rx Cons"}
    },

    -- Flight Mode Sensors
    governor = {
        name = "Governor State",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5125},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5450}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1205}
        },
        crsfLegacy = {"Flight mode"}
    },

    -- Adjustment Sensors
    adjF = {
        name = "Adjustment Sensors (Function)",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5110}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1221}
        },
        crsfLegacy = {nil}
    },
    adjV = {
        name = "Adjustment Sensors (Value)",
        mandatory = false,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5111}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1222}
        },
        crsfLegacy = {nil}
    },

    -- PID and Rate Profiles
    pidProfile = {
        name = "PID Profile",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5130},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5471}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1211}
        },
        crsfLegacy = {nil}
    },
    rateProfile = {
        name = "Rate Profile",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5131},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5472}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1212}
        },
        crsfLegacy = {nil}
    },

    -- Throttle Sensors
    throttlePercentage = {
        name = "Throttle %",
        mandatory = true,
        sport = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x51A4},
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x5440}
        },
        crsf = {
            {category = CATEGORY_TELEMETRY_SENSOR, appId = 0x1035}
        },
        crsfLegacy = {nil}
    }
}

-- Cache telemetry source
local tlm = system.getSource({category = CATEGORY_SYSTEM_EVENT, member = TELEMETRY_ACTIVE})

--- Retrieve the active telemetry protocol
---@return string
function telemetry.getSensorProtocol()
    return protocol
end

--- Function to list all sensors with key, name, and mandatory status
---@return table
function telemetry.listSensors()
    local sensorList = {}

    for key, sensor in pairs(sensorTable) do table.insert(sensorList, {key = key, name = sensor.name, mandatory = sensor.mandatory}) end

    return sensorList
end

--- Retrieve a sensor source by name
---@param name string
---@return any
function telemetry.getSensorSource(name)
    if not sensorTable[name] then return nil end

    -- Use cached value if available
    if sensors[name] then return sensors[name] end

    -- Helper function to check if MSP version conditions are met
    local function checkCondition(sensorEntry)
        if sensorEntry.mspgt then
            -- Check if API version exists and meets "greater than" condition
            return rfsuite.session and rfsuite.session.apiVersion and (rfsuite.utils.round(rfsuite.session.apiVersion,2) >= rfsuite.utils.round(sensorEntry.mspgt,2))
        elseif sensorEntry.msplt then
            -- Check if API version exists and meets "less than" condition
            return rfsuite.session and rfsuite.session.apiVersion and (rfsuite.utils.round(rfsuite.session.apiVersion,2) <= rfsuite.utils.round(sensorEntry.msplt,2))

        end
        -- No conditions = always valid
        return true
    end

    if rfsuite.session.rssiSensorType == "crsf" then
        if not crsfSOURCE then crsfSOURCE = system.getSource({category = CATEGORY_TELEMETRY_SENSOR, appId = 0xEE01}) end

        if crsfSOURCE then
            protocol = "crsf"
            for _, sensor in ipairs(sensorTable[name].crsf or {}) do
                -- Skip entries with unfulfilled version conditions
                if checkCondition(sensor) then
                    sensor.mspgt = nil
                    sensor.msplt = nil
                    local source = system.getSource(sensor)
                    if source then
                        sensors[name] = source
                        return sensors[name]
                    end
                end
            end
        else
            protocol = "crsfLegacy"
            for _, sensor in ipairs(sensorTable[name].crsfLegacy or {}) do
                local source = system.getSource(sensor)
                if source then
                    sensors[name] = source
                    return sensors[name]
                end
            end
        end
    elseif rfsuite.session.rssiSensorType == "sport" then
        protocol = "sport"
        for _, sensor in ipairs(sensorTable[name].sport or {}) do
            -- Skip entries with unfulfilled version conditions 
            if checkCondition(sensor) then
                sensor.mspgt = nil
                sensor.msplt = nil
                local source = system.getSource(sensor)
                if sensor.msplt then
                    print(source)
                end   
                if source then
                    sensors[name] = source
                    return sensors[name]
                end
            end
        end
    else
        protocol = "unknown"    
    end

    return nil -- If no valid sensor is found
end

--- Function to validate sensors with rate limiting
---@param returnValid boolean|nil Whether to return valid or invalid sensors
---@return table
function telemetry.validateSensors(returnValid)
    local now = os.clock()

    -- Return cached result if within rate limit
    if (now - lastValidationTime) < VALIDATION_RATE_LIMIT then return lastValidationResult end

    -- Update last validation time
    lastValidationTime = now

    if not telemetry.active() then
        local allSensors = {}
        for key, sensor in pairs(sensorTable) do table.insert(allSensors, {key = key, name = sensor.name}) end
        lastValidationResult = allSensors
        return allSensors
    end

    local resultSensors = {}

    for key, sensor in pairs(sensorTable) do
        local sensorSource = telemetry.getSensorSource(key)
        local isValid = sensorSource ~= nil and sensorSource:state() ~= false

        if returnValid then
            -- Include only valid sensors
            if isValid then table.insert(resultSensors, {key = key, name = sensor.name}) end
        else
            -- Include only invalid sensors, but consider mandatory flag
            if not isValid and sensor.mandatory ~= false then table.insert(resultSensors, {key = key, name = sensor.name}) end
        end
    end

    lastValidationResult = resultSensors
    return resultSensors
end

--- Check if telemetry is active
---@return boolean
function telemetry.active()
    if system.getVersion().simulation then return true end
    return telemetryState
end

--- Wakeup function to refresh telemetry state
function telemetry.wakeup()
    local now = os.clock()

    -- Prioritize MSP traffic
    if rfsuite.app.triggers.mspBusy then return end

    -- Rate-limited telemetry checks
    if (now - sensorRateLimit) >= SENSOR_RATE then
        sensorRateLimit = now
        telemetryState = tlm and tlm:state() or false
    end

    -- Periodic cache flush every 10 seconds
    if (now - lastCacheFlushTime) >= CACHE_FLUSH_INTERVAL then
        lastCacheFlushTime = now
        sensors = {} -- Reset cached sensors
        telemetrySOURCE, crsfSOURCE, protocol = nil, nil, nil
    end

    -- Reset if telemetry is inactive or RSSI sensor changed
    if not telemetry.active() or rfsuite.session.rssiSensorChanged then
        telemetrySOURCE, crsfSOURCE, protocol = nil, nil, nil
        sensors = {}
    end
end

return telemetry
