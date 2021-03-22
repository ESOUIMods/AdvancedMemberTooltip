-------------------------------------------------------------------------------
-- Advanced Member Tooltip v2.00
-------------------------------------------------------------------------------
-- Author: Arkadius
-- This Add-on is not created by, affiliated with or sponsored by ZeniMax Media
-- Inc. or its affiliates. The Elder Scrolls® and related logos are registered
-- trademarks or trademarks of ZeniMax Media Inc. in the United States and/or
-- other countries.
--
-- You can read the full terms at:
-- https://account.elderscrollsonline.com/add-on-terms
--
---------------------------------------------------------------------------------

local LGH                       = LibHistoire
local LAM                       = LibAddonMenu2
local AddonName = "AdvancedMemberTooltip"

AMT = {}
_, AMT.kioskCycle = GetGuildKioskCycleTimes()
AMT.LibHistoireGeneralListener = {}
AMT.LibHistoireBankListener = {}
AMT.GeneralEventsNeedProcessing = {}
AMT.GeneralTimeEstimated = {}
AMT.BankEventsNeedProcessing = {}
AMT.BankTimeEstimated = {}
local weekCutoff = 0
local weekStart    = 0
local weekEnd      = 0
AMT.useSunday    = false
AMT.addToCutoff  = 0

AMT.savedData = {}
local defaultData = {
  lastReceivedGeneralEventID = {},
  lastReceivedBankEventID = {},
  EventProcessed = {},
  CurrentKioskTime = 0,
  useSunday    = false,
  addToCutoff  = 0,
}

local amtDefaults = {
  useSunday    = false,
  addToCutoff  = 0,
}


if LibDebugLogger then
  local logger          = LibDebugLogger.Create(AddonName)
  AMT.logger = logger
end
local SDLV = DebugLogViewer
if SDLV then AMT.viewer = true else AMT.viewer = false end

local function create_log(log_type, log_content)
  if not AMT.viewer and log_type == "Info" then 
    CHAT_ROUTER:AddSystemMessage(log_content)
    return 
  end
  if not AMT.logger then return end
  if log_type == "Debug" then
    AMT.logger:Debug(log_content)
  end
  if log_type == "Info" then
    AMT.logger:Info(log_content)
  end
  if log_type == "Verbose" then
    AMT.logger:Verbose(log_content)
  end
  if log_type == "Warn" then
    AMT.logger:Warn(log_content)
  end
end

local function emit_message(log_type, text)
  if (text == "") then
  text = "[Empty String]"
  end
  create_log(log_type, text)
end

local function emit_table(log_type, t, indent, table_history)
  indent        = indent or "."
  table_history = table_history or {}

  for k, v in pairs(t) do
  local vType = type(v)

  emit_message(log_type, indent .. "(" .. vType .. "): " .. tostring(k) .. " = " .. tostring(v))

  if (vType == "table") then
    if (table_history[v]) then
    emit_message(log_type, indent .. "Avoiding cycle on table...")
    else
    table_history[v] = true
    emit_table(log_type, v, indent .. "  ", table_history)
    end
  end
  end
end

function AMT:dm(log_type, ...)
  for i = 1, select("#", ...) do
    local value = select(i, ...)
    if (type(value) == "table") then
      emit_table(log_type, value)
    else
      emit_message(log_type, tostring(value))
    end
  end
end

local lang = GetCVar('Language.2')
local langStrings = {
  en =
  {
    member      = "Member for %s%i %s",
    sinceLogoff = "Offline for %s%i %s",
    depositions = "Deposits",
    withdrawals = "Withdrawals",
    total       = "Total: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (over %i %s)",
    last        = "Last: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (%i %s ago)",
    minute      = "minute",
    hour        = "hour",
    day         = "day"
  },
  fr =
  {
    member      = "Membre pour %s%i %s",
    sinceLogoff = "Offline for %s%i %s",
    depositions = "Dépôts",
    withdrawals = "Retraits",
    total       = "Total: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (sur %i %s)",
    last        = "Dernier: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (%i %s depuis)",
    minute      = "minute",
    hour        = "heure",
    day         = "jour"
  },
  de =
  {
    member      = "Mitglied seit %s%i %s",
    sinceLogoff = "Offline for %s%i %s",
    depositions = "Einzahlungen",
    withdrawals = "Auszahlungen",
    total       = "Gesamt: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (innerhalb von %i %s)",
    last        = "Zuletzt: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (vor %i %s)",
    minute      = "Minute",
    hour        = "Stunde",
    day         = "Tag"
  },
  ru =
  {
    member      = "Member for %s%i %s",
    sinceLogoff = "Offline for %s%i %s",
    depositions = "Deposits",
    withdrawals = "Withdrawals",
    total       = "Total: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (over %i %s)",
    last        = "Last: %i |t16:16:EsoUI/Art/currency/currency_gold.dds|t (%i %s ago)",
    minute      = "minute",
    hour        = "hour",
    day         = "day"
  },
}

-- Hooked functions
local org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter = ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter
local org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit = ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit


local function secToTime(timeframe) -- in seconds
  local timeResult = math.floor(timeframe / 60)
  local str = langStrings[lang]["minute"]

  if (timeResult > 60) then
    timeResult = math.floor(timeframe / (60 * 60))

    if (timeResult > 24) then
      timeResult = math.floor(timeframe / (60 * 60 * 24))

      str = langStrings[lang]["day"]
    else
      str = langStrings[lang]["hour"]
    end
  end

  if (timeResult ~= 1) then
    if (lang == "en") then
      str = str .. 's'
    end

    if (lang == "de") then
      if (str == langStrings[lang]["day"]) then
        str = str .. 'en'
      else
        str = str .. 'n'
      end
    end
  end

  return timeResult, str
end

function ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter(control)
  org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter(control)

  local parent = control:GetParent()
  local data = ZO_ScrollList_GetData(parent)
  local guildName = GetGuildName(GUILD_SELECTOR.guildId) -- must be this case here
  local displayName = string.lower(data.displayName)
  local timeStamp = GetTimeStamp()

  local tooltip = data.characterName
  local num, str

  if (AMT.savedData[guildName] ~= nil) then
    if (AMT.savedData[guildName][displayName] ~= nil) then
      tooltip = tooltip .. "\n\n"

      if (AMT.savedData[guildName][displayName].timeJoined == 0) then
        num, str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL])
        tooltip = tooltip .. string.format(langStrings[lang]["member"], "> ", num, str) .. "\n"
      else
        num, str = secToTime(timeStamp - AMT.savedData[guildName][displayName].timeJoined)
        tooltip = tooltip .. string.format(langStrings[lang]["member"], "", num, str) .. "\n"
      end

      if AMT.savedData[guildName][displayName].playerStatusLastSeen == 0 then
        tooltip = tooltip .. "Player: Online" .. "\n\n"
      elseif AMT.savedData[guildName][displayName].playerStatusLastSeen == 4615674491 then
        tooltip = tooltip .. "Player: Unseen" .. "\n\n"
      else
        local secsSinceLogoff = timeStamp - AMT.savedData[guildName][displayName].playerStatusLastSeen
        if secsSinceLogoff < 0 then secsSinceLogoff = 0 end
        num, str = secToTime(secsSinceLogoff)
        tooltip = tooltip .. string.format(langStrings[lang]["sinceLogoff"], "", num, str) .. "\n\n"
      end

      tooltip = tooltip .. langStrings[lang]["depositions"] .. ':' .. "\n"
      num, str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK])
      tooltip = tooltip .. string.format(langStrings[lang]["total"], AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].total, num, str) .. "\n"

      if (AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast == 0) then
        num, str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK])
      else
        num, str = secToTime(timeStamp - AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast)
      end
      tooltip = tooltip .. string.format(langStrings[lang]["last"], AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].last, num, str) .. "\n\n"

      tooltip = tooltip .. langStrings[lang]["withdrawals"] .. ':' .. "\n"
      num, str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK])
      tooltip = tooltip .. string.format(langStrings[lang]["total"], AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].total, num, str) .. "\n"

      if (AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast == 0) then
        num, str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK])
      else
        num, str = secToTime(timeStamp - AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast)
      end
      tooltip = tooltip .. string.format(langStrings[lang]["last"], AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].last, num, str)
    end
  end

  InitializeTooltip(InformationTooltip, control, BOTTOM, 0, 0, TOPCENTER)
  SetTooltipText(InformationTooltip, tooltip)
end

function ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit(control)
  ClearTooltip(InformationTooltip)

  org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit(control)
end

function AMT.createGuild(guildName)
  if (AMT.savedData[guildName] == nil) then
    AMT.savedData[guildName] = {}
  end

  if (AMT.savedData[guildName]["oldestEvents"] == nil) then
    AMT.savedData[guildName]["oldestEvents"] = {}
  end

  if (AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL] == nil) then
    AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL] = 0
  end

  if (AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK] == nil) then
    AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_BANK] = 0
  end

  if (AMT.savedData[guildName]["lastScans"] == nil) then
    AMT.savedData[guildName]["lastScans"] = {}
  end

  if (AMT.savedData[guildName]["lastScans"][GUILD_HISTORY_GENERAL] == nil) then
    AMT.savedData[guildName]["lastScans"][GUILD_HISTORY_GENERAL] = 0
  end

  if (AMT.savedData[guildName]["lastScans"][GUILD_HISTORY_BANK] == nil) then
    AMT.savedData[guildName]["lastScans"][GUILD_HISTORY_BANK] = 0
  end
end

function AMT:createUser(guildName, displayName)
  if AMT.savedData[guildName] == nil then AMT.savedData[guildName] = {} end
  if (AMT.savedData[guildName][displayName] == nil) then
    AMT.savedData[guildName][displayName] = {}
    AMT.savedData[guildName][displayName].timeJoined = 0
    AMT.savedData[guildName][displayName].playerStatusOnline = false
    AMT.savedData[guildName][displayName].playerStatusOffline = false
    AMT.savedData[guildName][displayName].playerStatusLastSeen = 4615674491
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED] = {}
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeFirst = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].last = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].total = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED] = {}
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeFirst = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].last = 0
    AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].total = 0
  end
end

function AMT.resetUser(guildName, displayName)
  if AMT.savedData[guildName] == nil then AMT.savedData[guildName] = {} end
  if (AMT.savedData[guildName][displayName] == nil) then
    AMT:createUser(guildName, displayName)
  end
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast = 0
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].last = 0
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].total = 0
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast = 0
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].last = 0
  AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].total = 0
end

function AMT.processEvent(guildID, category, theEvent)
  if AMT.savedData["EventProcessed"][theEvent.eventId] == nil then
    AMT.savedData["EventProcessed"][theEvent.eventId] = true
  else
    return
  end

  -- seemed to be correct but later gives odd result
  -- local timeStamp = GetTimeStamp() - theEvent.evTime
  local timeStamp = theEvent.evTime
  local guildName = GetGuildName(guildID)
  local displayName = string.lower(theEvent.evName)

  if AMT.savedData[guildName]["oldestEvents"][category] == 0 or AMT.savedData[guildName]["oldestEvents"][category] > timeStamp then AMT.savedData[guildName]["oldestEvents"][category] = timeStamp end

  if (theEvent.evType == GUILD_EVENT_GUILD_JOIN) then
    if (AMT.savedData[guildName][displayName].timeJoined < timeStamp) then
      AMT.savedData[guildName][displayName].timeJoined = timeStamp
      --AMT:dm("Debug", "General Event")
    end
  end

  if (category == GUILD_HISTORY_BANK) and (theEvent.evTime > weekStart) then
    if (theEvent.evType == GUILD_EVENT_BANKGOLD_ADDED) or (theEvent.evType == GUILD_EVENT_BANKGOLD_REMOVED) then
      AMT.savedData[guildName][displayName][theEvent.evType].total = AMT.savedData[guildName][displayName][theEvent.evType].total + theEvent.evGold
      AMT.savedData[guildName][displayName][theEvent.evType].last = theEvent.evGold
      AMT.savedData[guildName][displayName][theEvent.evType].timeLast = timeStamp
      --AMT:dm("Debug", "Bank Event")

      if (AMT.savedData[guildName][displayName][theEvent.evType].timeFirst == 0) then
        AMT.savedData[guildName][displayName][theEvent.evType].timeFirst = timeStamp
      end
    end

    AMT.savedData[guildName]["lastScans"][category] = timeStamp
  end

end

function AMT:SetupListener(guildID)
  -- LibHistoireListener
  -- lastReceivedEventID
  -- systemSavedVariables
  -- listener
  AMT.LibHistoireGeneralListener[guildID] = LGH:CreateGuildHistoryListener(guildID, GUILD_HISTORY_GENERAL)
  AMT.LibHistoireBankListener[guildID] = LGH:CreateGuildHistoryListener(guildID, GUILD_HISTORY_BANK)
  local lastReceivedGeneralEventID
  local lastReceivedBankEventID

  if AMT.savedData["lastReceivedGeneralEventID"][guildID] then
    --AMT:dm("Info", string.format("AMT Saved Var: %s, GuildID: (%s)", AMT.savedData["lastReceivedGeneralEventID"][guildID], guildID))
  lastReceivedGeneralEventID = StringToId64(AMT.savedData["lastReceivedGeneralEventID"][guildID]) or "0"
  --AMT:dm("Info", string.format("lastReceivedGeneralEventID set to: %s", lastReceivedGeneralEventID))
  AMT.LibHistoireGeneralListener[guildID]:SetAfterEventId(lastReceivedGeneralEventID)
  end

  if AMT.savedData["lastReceivedBankEventID"][guildID] then
    --AMT:dm("Info", string.format("AMT Saved Var: %s, GuildID: (%s)", AMT.savedData["lastReceivedBankEventID"][guildID], guildID))
  lastReceivedBankEventID = StringToId64(AMT.savedData["lastReceivedBankEventID"][guildID]) or "0"
  --AMT:dm("Info", string.format("lastReceivedBankEventID set to: %s", lastReceivedBankEventID))
  AMT.LibHistoireBankListener[guildID]:SetAfterEventId(lastReceivedBankEventID)
  end

  -- Begin Listener General
  AMT.LibHistoireGeneralListener[guildID]:SetEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
    if eventType == GUILD_EVENT_GUILD_JOIN then
      local param1 = p1 or ""
      local param2 = p2 or ""
      local param3 = p3 or ""
      local param4 = p4 or ""
      local param5 = p5 or ""
      local param6 = p6 or ""
      local theString = param1 .. param2 .. param3 .. param4 .. param5 .. param6

      if not lastReceivedGeneralEventID or CompareId64s(eventId, lastReceivedGeneralEventID) > 0 then
        AMT.savedData["lastReceivedGeneralEventID"][guildID] = Id64ToString(eventId)
        lastReceivedGeneralEventID                                                 = eventId
      end
      local theEvent    = {
        evType = eventType,
        evTime = eventTime,
        evName = p1, -- Username that joined the guild
        evGold = nil, -- because it is when user joined
        eventId = Id64ToString(eventId), -- eventId but new
      }
      AMT.processEvent(guildID, GUILD_HISTORY_GENERAL, theEvent)
    end
  end)

  -- Begin Listener Bank
  AMT.LibHistoireBankListener[guildID]:SetEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
    if (eventType == GUILD_EVENT_BANKGOLD_ADDED or eventType == GUILD_EVENT_BANKGOLD_REMOVED) then
      local param1 = p1 or ""
      local param2 = p2 or ""
      local param3 = p3 or ""
      local param4 = p4 or ""
      local param5 = p5 or ""
      local param6 = p6 or ""
      local theString = param1 .. param2 .. param3 .. param4 .. param5 .. param6

      if not lastReceivedBankEventID or CompareId64s(eventId, lastReceivedBankEventID) > 0 then
        AMT.savedData["lastReceivedBankEventID"][guildID] = Id64ToString(eventId)
        lastReceivedBankEventID                                                 = eventId
      end
      local theEvent    = {
        evType = eventType,
        evTime = eventTime,
        evName = p1, -- Username that joined the guild
        evGold = p2, -- The ammount of gold
        eventId = Id64ToString(eventId), -- eventId but new
      }
      AMT.processEvent(guildID, GUILD_HISTORY_BANK, theEvent)
    end
  end)

  -- Start Listeners
  AMT.LibHistoireGeneralListener[guildID]:Start()
  AMT.LibHistoireBankListener[guildID]:Start()
end

-- Setup LibHistoire listeners
function AMT:SetupListenerLibHistoire()
  AMT:dm("Debug", "SetupListenerLibHistoire")
  for i = 1, GetNumGuilds() do
    local guildID = GetGuildId(i)
    AMT.LibHistoireGeneralListener[guildID] = {}
    AMT.LibHistoireBankListener[guildID] = {}
    AMT:SetupListener(guildID)
  end
end

function AMT:KioskFlipListenerSetup()
  if AMT.savedData["CurrentKioskTime"] == AMT.kioskCycle then return end
  AMT:dm("Debug", "KioskFlipListenerSetup")
  AMT.savedData["CurrentKioskTime"] = AMT.kioskCycle
  AMT.savedData["EventProcessed"] = {}
  for i = 1, GetNumGuilds() do
    local guildID = GetGuildId(i)
    local guildName   = GetGuildName(guildID)
    for i = 1, GetNumGuildMembers(guildID), 1 do
      AMT.resetUser(guildName, string.lower(GetGuildMemberInfo(guildID, i)))
    end
    AMT.LibHistoireGeneralListener[guildID]:Stop()
    AMT.LibHistoireBankListener[guildID]:Stop()
    AMT.LibHistoireGeneralListener[guildID]  = nil
    AMT.LibHistoireBankListener[guildID]  = nil
    AMT.GeneralEventsNeedProcessing[guildID] = true
    AMT.BankEventsNeedProcessing[guildID] = true
    AMT.GeneralTimeEstimated[guildID]        = false
    AMT.BankTimeEstimated[guildID]        = false
  end

  for i = 1, GetNumGuilds() do
    local guildID                                    = GetGuildId(i)
    AMT.savedData["lastReceivedGeneralEventID"][guildID] = "0"
    AMT.savedData["lastReceivedBankEventID"][guildID]    = "0"
    AMT:SetupListener(guildID)
  end
  AMT:QueueCheckStatus()
end

function AMT:ExportGuildStats()
  local export    = ZO_SavedVars:NewAccountWide('AdvancedMemberTooltip', 1, "EXPORT", {}, nil)

  local numGuilds = GetNumGuilds()
  local guildNum  = self.guildNumber
  if guildNum > numGuilds then
    AMT:dm("Info", "Invalid Guild Number.")
    return
  end

  local guildID   = GetGuildId(guildNum)
  local guildName = GetGuildName(guildID)

  AMT:dm("Info", "Exporting: " .. guildName)
  export[guildName]     = {}
  local list            = export[guildName]

  local numGuildMembers = GetNumGuildMembers(guildID)
  for guildMemberIndex = 1, numGuildMembers do
    local displayName, _, _, _, _ = GetGuildMemberInfo(guildID, guildMemberIndex)
    displayNameKey = string.lower(displayName) -- because it's stored this way

    local amountDeposited = AMT.savedData[guildName][displayNameKey][GUILD_EVENT_BANKGOLD_ADDED].total or 0
    local amountWithdrawan = AMT.savedData[guildName][displayNameKey][GUILD_EVENT_BANKGOLD_REMOVED].total or 0
    local timeJoined = AMT.savedData[guildName][displayNameKey].timeJoined or 0
    local playerStatusLastSeen = AMT.savedData[guildName][displayNameKey].playerStatusLastSeen
    local timeStamp = GetTimeStamp()
    local timeStringOutput = ""
    local lastSeenString = ""

    if (playerStatusLastSeen == 4615674491) then
      lastSeenString = "Unseen"
    else
      local secsSinceLogoff = timeStamp - playerStatusLastSeen
      if secsSinceLogoff < 0 then secsSinceLogoff = 0 end
      local num, str = secToTime(secsSinceLogoff)
      lastSeenString = string.format("%i %s", num, str)
    end

    if (timeJoined == 0) then
      local timeValue, timeString = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL])
      timeStringOutput = string.format("= %s%i %s", "> ", timeValue, timeString)
    else
      local timeValue, timeString = secToTime(timeStamp - timeJoined)
      timeStringOutput = string.format("= %s%i %s", "", timeValue, timeString)
    end

    -- export normal case for displayName
    -- sample = "@displayName&timeJoined&amountDeposited&amountWithdrawan"
    table.insert(list, displayName .. " " .. timeStringOutput .. "&" .. lastSeenString .. "&" .. amountDeposited .. "&" .. amountWithdrawan)
  end
  AMT:dm("Info", "Guild Stats Export complete.  /reloadui to save the file.")
end

-- /script d(AMT.LibHistoireListener[622389]:GetPendingEventMetrics())
function AMT:CheckStatus()
  for i = 1, GetNumGuilds() do
    local guildID                                             = GetGuildId(i)
    local numGeneralEvents                                    = GetNumGuildEvents(guildID, GUILD_HISTORY_GENERAL)
    local numBankEvents                                       = GetNumGuildEvents(guildID, GUILD_HISTORY_BANK)
    local eventGeneralCount, processingGeneralSpeed, timeLeftGeneral = AMT.LibHistoireGeneralListener[guildID]:GetPendingEventMetrics()
    local eventBankCount, processingBankSpeed, timeLeftBank          = AMT.LibHistoireBankListener[guildID]:GetPendingEventMetrics()

    timeLeftGeneral = math.floor(timeLeftGeneral)
    timeLeftBank = math.floor(timeLeftBank)

    if timeLeftGeneral ~= -1 or processingGeneralSpeed ~= -1 then AMT.GeneralTimeEstimated[guildID] = true end
    if timeLeftBank ~= -1 or processingBankSpeed ~= -1 then AMT.BankTimeEstimated[guildID] = true end

    if (timeLeftGeneral == -1 and eventGeneralCount == 1 and numGeneralEvents == 0) and AMT.GeneralTimeEstimated[guildID] then AMT.GeneralEventsNeedProcessing[guildID] = false end
    if (timeLeftBank == -1 and eventBankCount == 1 and numBankEvents == 0) and AMT.BankTimeEstimated[guildID] then AMT.BankEventsNeedProcessing[guildID] = false end

    if eventGeneralCount == 0 and AMT.GeneralTimeEstimated[guildID] then AMT.GeneralEventsNeedProcessing[guildID] = false end
    if eventBankCount == 0 and AMT.BankTimeEstimated[guildID] then AMT.BankEventsNeedProcessing[guildID] = false end

    if timeLeftGeneral == 0 and AMT.GeneralTimeEstimated[guildID] then AMT.GeneralEventsNeedProcessing[guildID] = false end
    if timeLeftBank == 0 and AMT.BankTimeEstimated[guildID] then AMT.BankEventsNeedProcessing[guildID] = false end
  end
  for i = 1, GetNumGuilds() do
    local guildID = GetGuildId(i)
    if AMT.GeneralEventsNeedProcessing[guildID] then return true end
    if AMT.BankEventsNeedProcessing[guildID] then return true end
  end
  return false
end

function AMT:QueueCheckStatus()
  local eventsRemaining = AMT:CheckStatus()
  if eventsRemaining then
    zo_callLater(function() AMT:QueueCheckStatus() end, 60000) -- 60000 1 minute
    AMT:dm("Info", "LibHistoire AMT Refresh Not Finished Yet")
  else
    AMT:dm("Info", "LibHistoire AMT Refresh Finished")
  end
end

function AMT:DoRefresh()
  AMT:dm("Info", 'LibHistoire refreshing AMT...')
  numGuilds = GetNumGuilds()
  for i = 1, numGuilds do
    local guildID = GetGuildId(i)
    AMT.LibHistoireGeneralListener[guildID]:Stop()
    AMT.LibHistoireBankListener[guildID]:Stop()
    AMT.LibHistoireGeneralListener[guildID]  = nil
    AMT.LibHistoireBankListener[guildID]  = nil
    AMT.GeneralEventsNeedProcessing[guildID] = true
    AMT.BankEventsNeedProcessing[guildID] = true
    AMT.GeneralTimeEstimated[guildID]        = false
    AMT.BankTimeEstimated[guildID]        = false
  end
  for i = 1, numGuilds do
    local guildID                                    = GetGuildId(i)
    AMT.savedData["lastReceivedGeneralEventID"][guildID] = "0"
    AMT.savedData["lastReceivedBankEventID"][guildID]    = "0"
    AMT:SetupListener(guildID)
  end
  AMT:QueueCheckStatus()
end

function AMT:UpdatePlayerStatusLastSeen()
  AMT:dm("Debug", "UpdatePlayerStatusLastSeen")
  for i = 1, GetNumGuilds() do
    local guildID = GetGuildId(i)
    local guildName   = GetGuildName(guildID)
    for i = 1, GetNumGuildMembers(guildID), 1 do
      local displayName, note, rankIndex, playerStatus, secsSinceLogoff = GetGuildMemberInfo(guildID, i)
      displayName = string.lower(displayName)
      if AMT.savedData[guildName][displayName] == nil then AMT:createUser(guildName, displayName) end
      if AMT.savedData[guildName][displayName].playerStatusOffline == nil then AMT.savedData[guildName][displayName].playerStatusOffline = false end
      if AMT.savedData[guildName][displayName].playerStatusOnline == nil then AMT.savedData[guildName][displayName].playerStatusOnline = false end
      if AMT.savedData[guildName][displayName].playerStatusLastSeen == nil then AMT.savedData[guildName][displayName].playerStatusLastSeen = 4615674491 end

      if playerStatus == PLAYER_STATUS_ONLINE or playerStatus == PLAYER_STATUS_DO_NOT_DISTURB or playerStatus == PLAYER_STATUS_AWAY then
        AMT.savedData[guildName][displayName].playerStatusOnline = true
        AMT.savedData[guildName][displayName].playerStatusOffline = false
        AMT.savedData[guildName][displayName].playerStatusLastSeen = 0
      end
      if playerStatus == PLAYER_STATUS_OFFLINE and AMT.savedData[guildName][displayName].playerStatusLastSeen == 0 then
        AMT.savedData[guildName][displayName].playerStatusOffline = true
        AMT.savedData[guildName][displayName].playerStatusOnline = false
        AMT.savedData[guildName][displayName].playerStatusLastSeen = GetTimeStamp()
      end
    end
  end
end

function OnStatusChanged(eventCode, guildId, displayName, oldStatus, newStatus)
  local guildName   = GetGuildName(guildId)
  local name = string.lower(displayName)
  if not AMT.savedData[guildName][name] then 
    AMT:createUser(guildName, name) 
  end
  if AMT.savedData[guildName][name].playerStatusOffline == nil then AMT.savedData[guildName][name].playerStatusOffline = false end
  if AMT.savedData[guildName][name].playerStatusOnline == nil then AMT.savedData[guildName][name].playerStatusOnline = false end
  if AMT.savedData[guildName][name].playerStatusLastSeen == nil then AMT.savedData[guildName][name].playerStatusLastSeen = 4615674491 end

  if newStatus == PLAYER_STATUS_ONLINE or playerStatus == PLAYER_STATUS_DO_NOT_DISTURB or playerStatus == PLAYER_STATUS_AWAY then
    AMT.savedData[guildName][name].playerStatusOnline = true
    AMT.savedData[guildName][name].playerStatusOffline = false
    AMT.savedData[guildName][name].playerStatusLastSeen = 0
  end
  if newStatus == PLAYER_STATUS_OFFLINE and AMT.savedData[guildName][name].playerStatusLastSeen == 0 then
    AMT.savedData[guildName][name].playerStatusOffline = true
    AMT.savedData[guildName][name].playerStatusOnline = false
    AMT.savedData[guildName][name].playerStatusLastSeen = GetTimeStamp()
  end
end

function AMT.ModifySundayTime()
  local modifyStartTime = 0
  local addHours = 0
  if GetWorldName() == "NA Megaserver" then
    modifyStartTime = modifyStartTime + (3600 * 12) -- roll to midnight Tuesday
    modifyStartTime = modifyStartTime + (3600 * 48) -- roll to midnight Sunday
  else
    modifyStartTime = modifyStartTime + (3600 * 6) -- roll to midnight Tuesday
    modifyStartTime = modifyStartTime + (3600 * 48) -- roll to midnight Sunday
  end
  addHours = (3600 * AMT.savedData.addToCutoff) -- add additional hours past midnight 
  return modifyStartTime, addHours
end

function AMT.DoSundayTime()
  AMT:dm("Debug", "DoSundayTime")
  local modifyStartTime, addHours = AMT.ModifySundayTime()
  weekStart = weekStart - modifyStartTime
  weekStart = weekStart + addHours
  weekEnd = weekEnd - modifyStartTime
  weekEnd = weekEnd + addHours
  --[[
  AMT:dm("Info", "weekEnd = weekEnd - modifyStartTime")
  AMT:dm("Info", weekStart)
  AMT:dm("Info", weekEnd)
  AMT:dm("Info", os.date("%c", weekStart))
  AMT:dm("Info", os.date("%c", weekEnd))
  ]]--
  
  local timeString = "Cutoff Times: "
  local timeStart = os.date("%c", weekStart)
  local timeEnd = os.date("%c", weekEnd)
  
  timeString = timeString .. timeStart .. " / " .. timeEnd
  AMT:dm("Info", timeString)
end

function AMT.DoTuesdayTime()
  AMT:dm("Debug", "DoTuesdayTime")
  weekCutoff = AMT.kioskCycle
  weekStart    = weekCutoff - (7 * 86400) -- GetGuildKioskCycleTimes() minus 7 days
  weekEnd      = weekCutoff -- GetGuildKioskCycleTimes()

  local timeString = "Cutoff Times: "
  local timeStart = os.date("%c", weekStart)
  local timeEnd = os.date("%c", weekEnd)
  
  timeString = timeString .. timeStart .. " / " .. timeEnd
  if not AMT.savedData.useSunday then AMT:dm("Info", timeString) end
end

function AMT.Slash(allArgs)
  local args   = ""
  local guildNumber   = 0
  local exp2   = 0
  local argNum = 0
  for w in string.gmatch(allArgs, "%w+") do
    argNum = argNum + 1
    if argNum == 1 then args = w end
    if argNum == 2 then guildNumber = tonumber(w) end
    if argNum == 3 then exp2 = tonumber(w) end
  end
  args = string.lower(args)
  if args == "help" or args == "" then
    AMT:dm("Info", "/amt export <Guild number> - Exports Guild Statistics.")
    AMT:dm("Info", "/amt refresh - Refresh LibHistoire information without resetting data.")
    return
  end
  if args == 'export' then
    if (guildNumber > 0) and (GetNumGuilds() > 0) and (guildNumber <= GetNumGuilds()) then
      AMT.guildNumber = guildNumber
      AMT:ExportGuildStats()
    else
      AMT:dm("Info", "Please include the guild number you wish to export.")
      AMT:dm("Info", "For example '/amt export 1' to export guild 1.")
    end
    return
  end
  if args == 'refresh' then
    AMT:DoRefresh()
    return
  end
  AMT:dm("Info", string.format("[AMT] %s : is an unrecognized command.", args))
end

function AMT:LibAddonInit()
  AMT:dm("Debug", "LibAddonInit")
  local panelData = {
    type                = 'panel',
    name                = 'AdvancedMemberTooltip',
    displayName         = 'Advanced Member Tooltip',
    author              = 'Sharlikran',
    version             = '2.05',
    registerForRefresh  = true,
    registerForDefaults = true,
  }
  LAM:RegisterAddonPanel('AdvancedMemberTooltipOptions', panelData)

  local optionsData = {
    -- Open main window with mailbox scenes
    [1]  = {
      type    = 'checkbox',
      name    = "Use Sunday Cutoff",
      tooltip = "Use Sunday as the cutoff instead of the Tuesday Kiosk Flip.",
      getFunc = function() return AMT.savedData.useSunday end,
      setFunc = function(value)
        AMT.savedData.useSunday = value
        if not AMT.savedData.useSunday then
          AMT.savedData.addToCutoff = 0
        end
        AMT.DoTuesdayTime()
        if AMT.savedData.useSunday then AMT.DoSundayTime() end
      end,
      default = amtDefaults.useSunday,
    },
    [2] = {
      type    = 'slider',
      name    = "Add Hours Past Midnight",
      tooltip = "Add X amount of hours to midnight for cutoff time.",
      min     = 0,
      max     = 36,
      getFunc = function() return AMT.savedData.addToCutoff end,
      setFunc = function(value)
        AMT.savedData.addToCutoff = value
        AMT.DoTuesdayTime()
        if AMT.savedData.useSunday then AMT.DoSundayTime() end
      end,
      default = amtDefaults.addToCutoff,
      disabled = function() return not AMT.savedData.useSunday end,
    },
    [3] = {
        type = "description",
        title = "Note",
        text = "Use /amt refresh if you change this setting",
        width = "full",
    },
  }

  LAM:RegisterOptionControls('AdvancedMemberTooltipOptions', optionsData)
end

-- Will be called upon loading the addon
local function onAddOnLoaded(eventCode, addonName)
  if (addonName ~= AddonName) then
    return
  end
  
  AMT.savedData = ZO_SavedVars:NewAccountWide("AdvancedMemberTooltip", 1, nil, defaultData)
  AMT.DoTuesdayTime()
  if AMT.savedData.useSunday then AMT.DoSundayTime() end
  -- Set up /amt as a slash command toggle for the main window
  SLASH_COMMANDS['/amt'] = AMT.Slash
  for i = 1, GetNumGuilds() do
    local guildID = GetGuildId(i)
    local guildName   = GetGuildName(guildID)
    AMT.createGuild(guildName)
    for i = 1, GetNumGuildMembers(guildID), 1 do
      AMT:createUser(guildName, string.lower(GetGuildMemberInfo(guildID, i)))
    end
    if AMT.savedData["lastReceivedGeneralEventID"][guildID] == nil then AMT.savedData["lastReceivedGeneralEventID"][guildID] = "0" end
    if AMT.savedData["lastReceivedBankEventID"][guildID] == nil then AMT.savedData["lastReceivedBankEventID"][guildID] = "0" end
  end

  AMT:LibAddonInit()
  AMT:SetupListenerLibHistoire()
  AMT:KioskFlipListenerSetup()
  AMT:UpdatePlayerStatusLastSeen()

  EVENT_MANAGER:RegisterForEvent(AddonName, EVENT_GUILD_MEMBER_PLAYER_STATUS_CHANGED, OnStatusChanged)

  EVENT_MANAGER:UnregisterForEvent(AddonName, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(AddonName, EVENT_ADD_ON_LOADED, onAddOnLoaded)
