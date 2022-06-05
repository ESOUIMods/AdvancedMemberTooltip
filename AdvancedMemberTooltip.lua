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

local LGH = LibHistoire
local LAM = LibAddonMenu2
local AddonName = "AdvancedMemberTooltip"

AMT = {}

-------------------------------------------------
----- early helper                          -----
-------------------------------------------------

local function is_in(search_value, search_table)
  for k, v in pairs(search_table) do
    if search_value == v then return true end
    if type(search_value) == "string" then
      if string.find(string.lower(v), string.lower(search_value)) then return true end
    end
  end
  return false
end

-------------------------------------------------
----- lang setup                            -----
-------------------------------------------------

AMT.client_lang = GetCVar("Language.2")
AMT.effective_lang = nil
AMT.supported_lang = { "de", "en", "fr", }
if is_in(AMT.client_lang, AMT.supported_lang) then
  AMT.effective_lang = AMT.client_lang
else
  AMT.effective_lang = "en"
end
AMT.supported_lang = AMT.client_lang == AMT.effective_lang

-------------------------------------------------
----- mod                                   -----
-------------------------------------------------

_, AMT.kioskCycle = GetGuildKioskCycleTimes()
AMT.LibHistoireGeneralListener = {}
AMT.LibHistoireBankListener = {}
AMT.GeneralEventsNeedProcessing = {}
AMT.GeneralTimeEstimated = {}
AMT.BankEventsNeedProcessing = {}
AMT.BankTimeEstimated = {}
local weekCutoff = 0
local weekStart = 0
local weekEnd = 0
AMT.useSunday = false
AMT.addToCutoff = 0
AMT.libHistoireScanByTimestamp = false

AMT.savedData = {}
local defaultData = {
  lastReceivedGeneralEventID = {},
  lastReceivedBankEventID = {},
  EventProcessed = {},
  CurrentKioskTime = 0,
  useSunday = false,
  addToCutoff = 0,
  exportEpochTime = false,
  dateTimeFormat = 1,
}
local exampleGuildId = nil
if GetNumGuilds() >= 1 then
  exampleGuildId = GetGuildId(1)
end
AMT.exampleGuildFoundedDate = "1/1/2000"
if exampleGuildId then AMT.exampleGuildFoundedDate = GetGuildFoundedDate(exampleGuildId) end
AMT.dateFormats = { "mm.dd.yy", "dd.mm.yy", "yy.dd.mm", "yy.mm.dd", }
AMT.dateFormatValues = { 1, 2, 3, 4 }

local amtDefaults = {
  useSunday = false,
  addToCutoff = 0,
}

if LibDebugLogger then
  local logger = LibDebugLogger.Create(AddonName)
  AMT.logger = logger
end
local SDLV = DebugLogViewer
if SDLV then AMT.viewer = true else AMT.viewer = false end

local function create_log(log_type, log_content)
  if not AMT.viewer and log_type == "Info" then
    CHAT_ROUTER:AddSystemMessage(log_content)
    return
  end
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
  indent = indent or "."
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

-- Hooked functions
local org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter = ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter
local org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit = ZO_KeyboardGuildRosterRowDisplayName_OnMouseExit

local function secToTime(timeframe)
  local outputString = ""
  local nextTimeframe = 0
  local years = math.floor(math.modf(timeframe / 31540000))
  nextTimeframe = timeframe - (years * 31540000)
  local days = math.floor(math.modf(nextTimeframe / 86400))
  nextTimeframe = timeframe - (years * 31540000) - (days * 86400)
  local hours = math.floor(math.modf(nextTimeframe / 3600))
  nextTimeframe = timeframe - (years * 31540000) - (days * 86400) - (hours * 3600)
  local minutes = math.floor(math.modf(nextTimeframe / 60))
  nextTimeframe = timeframe - (years * 31540000) - (days * 86400) - (hours * 3600) - (minutes * 60)
  local seconds = nextTimeframe

  if years > 0 then
    outputString = outputString .. string.format(GetString(AMT_DATE_FORMAT_YEARS), years)
  end
  if days > 0 then
    outputString = outputString .. string.format(GetString(AMT_DATE_FORMAT_DAYS), days)
  end
  if hours > 0 then
    outputString = outputString .. string.format(GetString(AMT_DATE_FORMAT_HOURS), hours)
  end
  if minutes > 0 then
    outputString = outputString .. string.format(GetString(AMT_DATE_FORMAT_MINUTES), minutes)
  end
  if seconds > 0 then
    outputString = outputString .. string.format(GetString(AMT_DATE_FORMAT_SECONDS), seconds)
  end
  if outputString == "" then outputString = GetString(AMT_DATE_FORMAT_NONE) end
  return outputString
end

local function TrimTagString(str)
  local stringTrimmed = string.gsub(str, '{t:', '')
  stringTrimmed = string.gsub(stringTrimmed, '}', '')
  return stringTrimmed
end

local function BuildTagsTable(str)
  local t = {}
  local function helper(line)
    if line ~= "" then
      t[line] = true
    end
    return ""
  end
  helper((str:gsub("(.-)&&", helper)))
  if next(t) then return t end
end

function ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter(control)
  local tagTable = {}
  org_ZO_KeyboardGuildRosterRowDisplayName_OnMouseEnter(control)

  local parent = control:GetParent()
  local data = ZO_ScrollList_GetData(parent)
  if data and data.note then tagTable = BuildTagsTable(TrimTagString(data.note)) end
  --AMT:dm("Debug", tagTable)
  local guildId = GUILD_SELECTOR.guildId
  local viewDepositWithdraws = DoesPlayerHaveGuildPermission(guildId, GUILD_PERMISSION_BANK_VIEW_DEPOSIT_HISTORY) or DoesPlayerHaveGuildPermission(guildId, GUILD_PERMISSION_BANK_VIEW_WITHDRAW_HISTORY)
  local guildName = GetGuildName(guildId) -- must be this case here
  local foundedDate = AMT:GetGuildFoundedDate(guildId)
  local displayName = string.lower(data.displayName)
  local timeStamp = GetTimeStamp()
  local foundDisplayName, secsSinceLogoff
  for member = 1, GetNumGuildMembers(guildId), 1 do
    secsSinceLogoff = -1
    foundDisplayName = ""
    foundDisplayName, _, _, _, secsSinceLogoff = GetGuildMemberInfo(guildId, member)
    foundDisplayName = string.lower(foundDisplayName)
    if displayName == foundDisplayName then
      secsSinceLogoff = AMT:DetermineSecondsSinceLogoff(secsSinceLogoff, foundedDate, displayName)
      break
    end
  end

  local tooltip = data.characterName
  local num, str

  if (AMT.savedData[guildName] ~= nil) then
    if (AMT.savedData[guildName][displayName] ~= nil) then
      tooltip = tooltip .. "\n\n"

      if (AMT.savedData[guildName][displayName].timeJoined == 0) then
        str = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL])
        tooltip = tooltip .. zo_strformat(GetString(AMT_MEMBER), "> ", str) .. "\n"
      else
        str = secToTime(timeStamp - AMT.savedData[guildName][displayName].timeJoined)
        tooltip = tooltip .. zo_strformat(GetString(AMT_MEMBER), "", str) .. "\n"
      end

      if AMT.savedData[guildName][displayName].playerStatusOnline then
        tooltip = tooltip .. GetString(AMT_PLAYER_ONLINE)
        if viewDepositWithdraws then
          tooltip = tooltip .. "\n\n"
        end
      else
        str = secToTime(secsSinceLogoff)
        tooltip = tooltip .. zo_strformat(GetString(AMT_SINCE_LOGOFF), "", str)
        if viewDepositWithdraws then
          tooltip = tooltip .. "\n\n"
        end
      end

      if viewDepositWithdraws then
        tooltip = tooltip .. GetString(AMT_DEPOSITS) .. ':' .. "\n"
        if (AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast == 0) then
          str = secToTime(AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast)
        else
          oldest = AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].timeLast
          timeframe = timeStamp - oldest
          str = secToTime(timeframe)
        end
        tooltip = tooltip .. string.format(GetString(AMT_TOTAL),
          AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].total, str) .. "\n"

        tooltip = tooltip .. string.format(GetString(AMT_LAST),
          AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_ADDED].last, str) .. "\n\n"

        tooltip = tooltip .. GetString(AMT_WITHDRAWALS) .. ':' .. "\n"
        if (AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast == 0) then
          str = secToTime(AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast)
        else
          oldest = AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].timeLast
          timeframe = timeStamp - oldest
          str = secToTime(timeframe)
        end

        tooltip = tooltip .. string.format(GetString(AMT_TOTAL),
          AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].total, str) .. "\n"

        tooltip = tooltip .. string.format(GetString(AMT_LAST),
          AMT.savedData[guildName][displayName][GUILD_EVENT_BANKGOLD_REMOVED].last, str) .. "\n"
      end -- end viewDepositWithdraws

      if tagTable and tagTable["gd"] then
        tooltip = tooltip .. "Deposited Weekly gold" .. "\n"
      end

      if tagTable and tagTable["sm"] then
        tooltip = tooltip .. "Weekly Sales Met"
      end

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

function AMT.processListenerEvent(guildId, category, theEvent)
  if AMT.savedData["EventProcessed"][theEvent.eventId] == nil then
    AMT.savedData["EventProcessed"][theEvent.eventId] = true
  else
    return
  end

  -- seemed to be correct but later gives odd result
  -- local timeStamp = GetTimeStamp() - theEvent.evTime
  local timeStamp = theEvent.evTime
  local guildName = GetGuildName(guildId)
  local displayName = string.lower(theEvent.evName)

  if AMT.savedData[guildName]["oldestEvents"][category] == 0 or AMT.savedData[guildName]["oldestEvents"][category] > timeStamp then AMT.savedData[guildName]["oldestEvents"][category] = timeStamp end

  if (theEvent.evType == GUILD_EVENT_GUILD_JOIN) then
    if (AMT.savedData[guildName][displayName].timeJoined ~= timeStamp) then
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

function AMT:SetupListener(guildId)
  -- LibHistoireListener
  -- lastReceivedEventID
  -- systemSavedVariables
  -- listener
  AMT.LibHistoireGeneralListener[guildId] = LGH:CreateGuildHistoryListener(guildId, GUILD_HISTORY_GENERAL)
  AMT.LibHistoireBankListener[guildId] = LGH:CreateGuildHistoryListener(guildId, GUILD_HISTORY_BANK)
  local lastReceivedGeneralEventID
  local lastReceivedBankEventID

  if AMT.savedData["lastReceivedGeneralEventID"][guildId] then
    --AMT:dm("Info", string.format("AMT Saved Var: %s, guildId: (%s)", AMT.savedData["lastReceivedGeneralEventID"][guildId], guildId))
    lastReceivedGeneralEventID = StringToId64(AMT.savedData["lastReceivedGeneralEventID"][guildId]) or "0"
    --AMT:dm("Info", string.format("lastReceivedGeneralEventID set to: %s", lastReceivedGeneralEventID))
    AMT.LibHistoireGeneralListener[guildId]:SetAfterEventId(lastReceivedGeneralEventID)
  end

  if AMT.libHistoireScanByTimestamp then
    local setAfterTimestamp = AMT.kioskCycle - (ZO_ONE_DAY_IN_SECONDS * 7)
    AMT.LibHistoireBankListener[guildId]:SetAfterEventTime(setAfterTimestamp)
  else
    if AMT.savedData["lastReceivedBankEventID"][guildId] then
      --AMT:dm("Info", string.format("AMT Saved Var: %s, guildId: (%s)", AMT.savedData["lastReceivedBankEventID"][guildId], guildId))
      lastReceivedBankEventID = StringToId64(AMT.savedData["lastReceivedBankEventID"][guildId]) or "0"
      --AMT:dm("Info", string.format("lastReceivedBankEventID set to: %s", lastReceivedBankEventID))
      AMT.LibHistoireBankListener[guildId]:SetAfterEventId(lastReceivedBankEventID)
    end
  end

  -- Begin Listener General
  AMT.LibHistoireGeneralListener[guildId]:SetEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
    if eventType == GUILD_EVENT_GUILD_JOIN then
      local param1 = p1 or ""
      local param2 = p2 or ""
      local param3 = p3 or ""
      local param4 = p4 or ""
      local param5 = p5 or ""
      local param6 = p6 or ""
      local theString = param1 .. param2 .. param3 .. param4 .. param5 .. param6

      if not lastReceivedGeneralEventID or CompareId64s(eventId, lastReceivedGeneralEventID) > 0 then
        AMT.savedData["lastReceivedGeneralEventID"][guildId] = Id64ToString(eventId)
        lastReceivedGeneralEventID = eventId
      end
      local theEvent = {
        evType = eventType,
        evTime = eventTime,
        evName = p1, -- Username that joined the guild
        evGold = nil, -- because it is when user joined
        eventId = Id64ToString(eventId), -- eventId but new
      }
      local guildName = GetGuildName(guildId)
      local displayName = string.lower(theEvent.evName)
      if not AMT.savedData[guildName][displayName] then AMT:createUser(guildName, displayName) end
      AMT.processListenerEvent(guildId, GUILD_HISTORY_GENERAL, theEvent)
    end
  end)

  -- Begin Listener Bank
  AMT.LibHistoireBankListener[guildId]:SetEventCallback(function(eventType, eventId, eventTime, p1, p2, p3, p4, p5, p6)
    if (eventType == GUILD_EVENT_BANKGOLD_ADDED or eventType == GUILD_EVENT_BANKGOLD_REMOVED) then
      local param1 = p1 or ""
      local param2 = p2 or ""
      local param3 = p3 or ""
      local param4 = p4 or ""
      local param5 = p5 or ""
      local param6 = p6 or ""
      local theString = param1 .. param2 .. param3 .. param4 .. param5 .. param6

      if not lastReceivedBankEventID or CompareId64s(eventId, lastReceivedBankEventID) > 0 then
        AMT.savedData["lastReceivedBankEventID"][guildId] = Id64ToString(eventId)
        lastReceivedBankEventID = eventId
      end
      local theEvent = {
        evType = eventType,
        evTime = eventTime,
        evName = p1, -- Username that joined the guild
        evGold = p2, -- The ammount of gold
        eventId = Id64ToString(eventId), -- eventId but new
      }
      AMT.processListenerEvent(guildId, GUILD_HISTORY_BANK, theEvent)
    end
  end)

  -- Start Listeners
  AMT.LibHistoireGeneralListener[guildId]:Start()
  AMT.LibHistoireBankListener[guildId]:Start()
end

-- Setup LibHistoire listeners
function AMT:SetupListenerLibHistoire()
  AMT:dm("Debug", "SetupListenerLibHistoire")
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    AMT.LibHistoireGeneralListener[guildId] = {}
    AMT.LibHistoireBankListener[guildId] = {}
    AMT:SetupListener(guildId)
  end
end

function AMT:KioskFlipListenerSetup()
  if AMT.savedData["CurrentKioskTime"] == AMT.kioskCycle then return end
  AMT:dm("Debug", "KioskFlipListenerSetup")
  AMT.libHistoireScanByTimestamp = true
  AMT.savedData["CurrentKioskTime"] = AMT.kioskCycle
  AMT.savedData["EventProcessed"] = {}
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    local guildName = GetGuildName(guildId)
    for member = 1, GetNumGuildMembers(guildId), 1 do
      AMT.resetUser(guildName, string.lower(GetGuildMemberInfo(guildId, member)))
    end
    AMT.LibHistoireGeneralListener[guildId]:Stop()
    AMT.LibHistoireBankListener[guildId]:Stop()
    AMT.LibHistoireGeneralListener[guildId] = nil
    AMT.LibHistoireBankListener[guildId] = nil
    AMT.GeneralEventsNeedProcessing[guildId] = true
    AMT.BankEventsNeedProcessing[guildId] = true
    AMT.GeneralTimeEstimated[guildId] = false
    AMT.BankTimeEstimated[guildId] = false
  end

  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    AMT.savedData["lastReceivedGeneralEventID"][guildId] = "0"
    AMT.savedData["lastReceivedBankEventID"][guildId] = "0"
    AMT:SetupListener(guildId)
  end
  AMT:QueueCheckStatus()
end

function AMT:ExportGuildStats()
  local export = ZO_SavedVars:NewAccountWide('AdvancedMemberTooltip', 1, "EXPORT", {}, nil)

  local numGuilds = GetNumGuilds()
  local guildNum = self.guildNumber
  if guildNum > numGuilds then
    AMT:dm("Info", "Invalid Guild Number.")
    return
  end

  local guildId = GetGuildId(guildNum)
  local guildName = GetGuildName(guildId)

  AMT:dm("Info", "Exporting: " .. guildName)
  export[guildName] = {}
  local list = export[guildName]

  local numGuildMembers = GetNumGuildMembers(guildId)
  local foundedDate = AMT:GetGuildFoundedDate(guildId)
  local displayName, secsSinceLogoff
  for guildMemberIndex = 1, numGuildMembers do
    displayName, _, _, _, secsSinceLogoff = GetGuildMemberInfo(guildId, guildMemberIndex)
    -- because it's stored with lower case
    displayNameKey = string.lower(displayName)
    secsSinceLogoff = AMT:DetermineSecondsSinceLogoff(secsSinceLogoff, foundedDate,
      displayName)
    if AMT.savedData[guildName][displayNameKey] then

      local amountDeposited = AMT.savedData[guildName][displayNameKey][GUILD_EVENT_BANKGOLD_ADDED].total or 0
      local amountWithdrawan = AMT.savedData[guildName][displayNameKey][GUILD_EVENT_BANKGOLD_REMOVED].total or 0
      local timeJoined = AMT.savedData[guildName][displayNameKey].timeJoined or 0
      local timeStamp = GetTimeStamp()
      local timeStringOutput = ""
      local lastSeenString = ""

      if (timeJoined == 0) then
        local timeString = secToTime(timeStamp - AMT.savedData[guildName]["oldestEvents"][GUILD_HISTORY_GENERAL])
        timeStringOutput = string.format(" = %s %s", "> ", timeString)
      else
        local timeString = secToTime(timeStamp - timeJoined)
        timeStringOutput = string.format(" = %s %s", "", timeString)
      end

      local str = secToTime(secsSinceLogoff)
      lastSeenString = string.format("%s", str)

      if AMT.savedData.exportEpochTime then
        timeStringOutput = "&" .. AMT.savedData[guildName][displayNameKey].timeJoined
        lastSeenString = timeStamp - secsSinceLogoff
        if timeJoined == 0 then
          --[[Until I figure out something better if the guild history
          does not go back far enough their timeJoined is 0. So show
          that is when ESO Launched for sorting and not founded date
          ]]--
          timeStringOutput = "&" .. 1396594800
        end
      end

      -- export normal case for displayName
      -- sample = "@displayName&timeJoined&amountDeposited&amountWithdrawan"
      table.insert(list,
        displayName .. timeStringOutput .. "&" .. lastSeenString .. "&" .. amountDeposited .. "&" .. amountWithdrawan)
    end
  end
  AMT:dm("Info", "Guild Stats Export complete.  /reloadui to save the file.")
end

-- /script d(AMT.LibHistoireListener[622389]:GetPendingEventMetrics())
function AMT:CheckStatus()
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    local guildName = GetGuildName(guildId)
    local numGeneralEvents = GetNumGuildEvents(guildId, GUILD_HISTORY_GENERAL)
    local numBankEvents = GetNumGuildEvents(guildId, GUILD_HISTORY_BANK)
    local eventGeneralCount, processingGeneralSpeed, timeLeftGeneral = AMT.LibHistoireGeneralListener[guildId]:GetPendingEventMetrics()
    local eventBankCount, processingBankSpeed, timeLeftBank = AMT.LibHistoireBankListener[guildId]:GetPendingEventMetrics()

    timeLeftGeneral = math.floor(timeLeftGeneral)
    timeLeftBank = math.floor(timeLeftBank)

    if timeLeftGeneral ~= -1 or processingGeneralSpeed ~= -1 then AMT.GeneralTimeEstimated[guildId] = true end
    if timeLeftBank ~= -1 or processingBankSpeed ~= -1 then AMT.BankTimeEstimated[guildId] = true end

    if (numGeneralEvents == 0 and eventGeneralCount == 1 and processingGeneralSpeed == -1 and timeLeftGeneral == -1) then
      AMT.GeneralTimeEstimated[guildId] = true
      AMT.GeneralEventsNeedProcessing[guildId] = false
    end

    if (numBankEvents == 0 and eventBankCount == 1 and processingBankSpeed == -1 and timeLeftBank == -1) then
      AMT.BankTimeEstimated[guildId] = true
      AMT.BankEventsNeedProcessing[guildId] = false
    end

    if eventGeneralCount == 0 and AMT.GeneralTimeEstimated[guildId] then AMT.GeneralEventsNeedProcessing[guildId] = false end
    if eventBankCount == 0 and AMT.BankTimeEstimated[guildId] then AMT.BankEventsNeedProcessing[guildId] = false end

    if timeLeftGeneral == 0 and AMT.GeneralTimeEstimated[guildId] then AMT.GeneralEventsNeedProcessing[guildId] = false end
    if timeLeftBank == 0 and AMT.BankTimeEstimated[guildId] then AMT.BankEventsNeedProcessing[guildId] = false end

    --AMT:dm("Debug", string.format("%s: numGeneralEvents: %s eventCount: %s processingSpeed: %s timeLeft: %s", guildName, numGeneralEvents, eventGeneralCount, processingGeneralSpeed, timeLeftGeneral))
    --AMT:dm("Debug", string.format("%s: numBankEvents: %s eventBankCount: %s processingBankSpeed: %s timeLeftBank: %s", guildName, numBankEvents, eventBankCount, processingBankSpeed, timeLeftBank))

  end
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    if AMT.GeneralEventsNeedProcessing[guildId] then return true end
    if AMT.BankEventsNeedProcessing[guildId] then return true end
  end
  return false
end

function AMT:QueueCheckStatus()
  local eventsRemaining = AMT:CheckStatus()
  if eventsRemaining then
    zo_callLater(function() AMT:QueueCheckStatus() end, ZO_ONE_MINUTE_IN_MILLISECONDS)
    AMT:dm("Info", "LibHistoire AMT Refresh Not Finished Yet")
  else
    AMT:dm("Info", "LibHistoire AMT Refresh Finished")
    AMT.libHistoireScanByTimestamp = false
  end
end

function AMT:DoRefresh()
  AMT:dm("Info", 'LibHistoire refreshing AMT...')
  AMT.libHistoireScanByTimestamp = true
  numGuilds = GetNumGuilds()
  for guildNum = 1, numGuilds do
    local guildId = GetGuildId(guildNum)
    AMT.LibHistoireGeneralListener[guildId]:Stop()
    AMT.LibHistoireBankListener[guildId]:Stop()
    AMT.LibHistoireGeneralListener[guildId] = nil
    AMT.LibHistoireBankListener[guildId] = nil
    AMT.GeneralEventsNeedProcessing[guildId] = true
    AMT.BankEventsNeedProcessing[guildId] = true
    AMT.GeneralTimeEstimated[guildId] = false
    AMT.BankTimeEstimated[guildId] = false
  end
  for guildNum = 1, numGuilds do
    local guildId = GetGuildId(guildNum)
    AMT.savedData["lastReceivedGeneralEventID"][guildId] = "0"
    AMT.savedData["lastReceivedBankEventID"][guildId] = "0"
    AMT:SetupListener(guildId)
  end
  AMT:QueueCheckStatus()
end

function table_sort(a, sortfield)
  local new1 = {}
  local new2 = {}
  for k, v in pairs(a) do
    table.insert(new1, { key = k, val = v })
  end
  table.sort(new1, function(a, b) return (a.val[sortfield] < b.val[sortfield]) end)
  for k, v in pairs(new1) do
    table.insert(new2, v.val)
  end
  return new2
end

function get_formatted_date_parts(date_str, date_format)
  local d, m, y, arr, x, yy, mm, dd, use_month_names
  local months = { jan = 1, feb = 2, mar = 3, apr = 4, may = 5, jun = 6, jul = 7, aug = 8, sep = 9, oct = 10, nov = 11, dec = 12 }

  if (date_format) then

    if string.find(date_format, "mmm") then
      use_month_names = true
    else
      use_month_names = false
    end

    d = string.find(date_format, "dd")
    m = string.find(date_format, "mm")
    y = string.find(date_format, "yy")

    arr = { { pos = y, b = "yy" }, { pos = m, b = "mm" }, { pos = d, b = "dd" } }
    arr = table_sort(arr, "pos")

    date_format = string.gsub(date_format, "yyyy", "(%%d+)")
    date_format = string.gsub(date_format, "mmm", "(%%a+)")
    date_format = string.gsub(date_format, "yy", "(%%d+)")
    date_format = string.gsub(date_format, "mm", "(%%d+)")
    date_format = string.gsub(date_format, "dd", "(%%d+)")
    date_format = string.gsub(date_format, " ", "%%s")
  else
    date_format = "(%d+)-(%d+)-(%d+)"
    arr = { { pos = 1, b = "yy" }, { pos = 2, b = "mm" }, { pos = 3, b = "dd" } }
  end

  if (date_str and date_str ~= "") then
    _, _, arr[1].c, arr[2].c, arr[3].c = string.find(string.lower(date_str), date_format)
  else
    return nil, nil, nil
  end

  arr = table_sort(arr, "b")
  yy = arr[3].c
  mm = arr[2].c
  dd = arr[1].c

  if (use_month_names) then

    mm = months[lower(string.sub(mm, 1, 3))]
    if (not mm) then
      error("Invalid month name.")
    end
  end

  -- for naughty people who still use two digit years.

  if (string.len(yy) == 2) then
    if (tonumber(yy) > 40) then
      yy = "19" .. yy
    else
      yy = "20" .. yy
    end
  end

  return tonumber(dd), tonumber(mm), tonumber(yy)
end

function AMT:GetGuildFoundedDate(guildId)
  local dateString = GetGuildFoundedDate(guildId)
  -- AMT:dm("Debug", dateString)
  local dateFormat = AMT.dateFormats[AMT.savedData.dateTimeFormat]
  local day, month, year = get_formatted_date_parts(dateString, dateFormat)
  -- AMT:dm("Debug", string.format("day: %s, month: %s, year: %s", day, month, year))
  local epochTime = os.time { year = year, month = month, day = day, hour = 0 }
  if not year then
    epochTime = 1396594800 -- ESO Launch
  end
  return epochTime
end

function AMT:DetermineSecondsSinceLogoff(secsSinceLogoff, foundedDate, displayName)
  local somethingDone = false
  local resultNum = secsSinceLogoff
  if secsSinceLogoff > foundedDate then
    --AMT:dm("Debug", "secsSinceLogoff > foundedDate")
    --AMT:dm("Debug", displayName)
    --AMT:dm("Debug", secsSinceLogoff)
    --AMT:dm("Debug", foundedDate)
    resultNum = GetTimeStamp() - secsSinceLogoff
    somethingDone = true
  end
  --[[ if the sec is more then 1577836800 or Wednesday, January 1, 2020
  then it might be a time stamp but not 624 months or 12 years ago
  ]]--
  if secsSinceLogoff > 1577836800 then
    --AMT:dm("Debug", "secsSinceLogoff > 31540000")
    --AMT:dm("Debug", displayName)
    --AMT:dm("Debug", secsSinceLogoff)
    --AMT:dm("Debug", foundedDate)
    resultNum = GetTimeStamp() - secsSinceLogoff
    somethingDone = true
  end
  if not somethingDone then
    --AMT:dm("Debug", "Maybe it is correct")
    --AMT:dm("Debug", displayName)
    --AMT:dm("Debug", secsSinceLogoff)
    --AMT:dm("Debug", foundedDate)
  end
  return resultNum
end

function AMT:UpdatePlayerStatusLastSeen()
  AMT:dm("Debug", "UpdatePlayerStatusLastSeen")
  local displayName, playerStatus, secsSinceLogoff
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    local guildName = GetGuildName(guildId)
    local foundedDate = AMT:GetGuildFoundedDate(guildId)
    for member = 1, GetNumGuildMembers(guildId), 1 do
      displayName, _, _, playerStatus, secsSinceLogoff = GetGuildMemberInfo(guildId, member)
      -- because it's stored with lower case names
      displayName = string.lower(displayName)
      secsSinceLogoff = AMT:DetermineSecondsSinceLogoff(secsSinceLogoff, foundedDate, displayName)
      if AMT.savedData[guildName][displayName] == nil then AMT:createUser(guildName, displayName) end
      if AMT.savedData[guildName][displayName].playerStatusOffline == nil then AMT.savedData[guildName][displayName].playerStatusOffline = false end
      if AMT.savedData[guildName][displayName].playerStatusOnline == nil then AMT.savedData[guildName][displayName].playerStatusOnline = false end
      if AMT.savedData[guildName][displayName].playerStatusLastSeen then
        AMT.savedData[guildName][displayName].playerStatusLastSeen = nil
      end
      if AMT.savedData[guildName][displayName].secsSinceLogoff then
        AMT.savedData[guildName][displayName].secsSinceLogoff = nil
      end

      if playerStatus == PLAYER_STATUS_ONLINE or playerStatus == PLAYER_STATUS_DO_NOT_DISTURB or playerStatus == PLAYER_STATUS_AWAY then
        AMT.savedData[guildName][displayName].playerStatusOnline = true
        AMT.savedData[guildName][displayName].playerStatusOffline = false
      end
      if playerStatus == PLAYER_STATUS_OFFLINE then
        AMT.savedData[guildName][displayName].playerStatusOffline = true
        AMT.savedData[guildName][displayName].playerStatusOnline = false
      end
    end
  end
end

function OnStatusChanged(eventCode, guildId, displayName, oldStatus, newStatus)
  local guildName = GetGuildName(guildId)
  local name = string.lower(displayName)

  if AMT.savedData[guildName] == nil then AMT.createGuild(guildName) end
  if AMT.savedData[guildName][name] == nil then AMT:createUser(guildName, name) end

  if newStatus == PLAYER_STATUS_ONLINE or newStatus == PLAYER_STATUS_DO_NOT_DISTURB or newStatus == PLAYER_STATUS_AWAY then
    AMT.savedData[guildName][name].playerStatusOnline = true
    AMT.savedData[guildName][name].playerStatusOffline = false
  end
  if newStatus == PLAYER_STATUS_OFFLINE then
    AMT.savedData[guildName][name].playerStatusOffline = true
    AMT.savedData[guildName][name].playerStatusOnline = false
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
  weekStart = weekCutoff - (ZO_ONE_DAY_IN_SECONDS * 7)
  weekEnd = weekCutoff -- GetGuildKioskCycleTimes()

  local timeString = "Cutoff Times: "
  local timeStart = os.date("%c", weekStart)
  local timeEnd = os.date("%c", weekEnd)

  timeString = timeString .. timeStart .. " / " .. timeEnd
  if not AMT.savedData.useSunday then AMT:dm("Info", timeString) end
end

function AMT.Slash(allArgs)
  local args = ""
  local guildNumber = 0
  local exp2 = 0
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
  if args == 'fullrefresh' then
    AMT.savedData["CurrentKioskTime"] = 1396594800
    AMT:KioskFlipListenerSetup()
    return
  end
  AMT:dm("Info", string.format("[AMT] %s : is an unrecognized command.", args))
end

function AMT:LibAddonInit()
  AMT:dm("Debug", "LibAddonInit")
  local panelData = {
    type = 'panel',
    name = 'AdvancedMemberTooltip',
    displayName = 'Advanced Member Tooltip',
    author = 'Sharlikran',
    version = '2.17',
    registerForRefresh = true,
    registerForDefaults = true,
  }
  LAM:RegisterAddonPanel('AdvancedMemberTooltipOptions', panelData)

  local optionsData = {
    -- Open main window with mailbox scenes
    [1] = {
      type = "header",
      name = "Cutoff Options",
      width = "full",
    },
    [2] = {
      type = 'checkbox',
      name = "Use Sunday Cutoff",
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
    [3] = {
      type = 'slider',
      name = "Add Hours Past Midnight",
      tooltip = "Add X amount of hours to midnight for cutoff time.",
      min = 0,
      max = 36,
      getFunc = function() return AMT.savedData.addToCutoff end,
      setFunc = function(value)
        AMT.savedData.addToCutoff = value
        AMT.DoTuesdayTime()
        if AMT.savedData.useSunday then AMT.DoSundayTime() end
      end,
      default = amtDefaults.addToCutoff,
      disabled = function() return not AMT.savedData.useSunday end,
    },
    [4] = {
      type = "description",
      title = "Note",
      text = "Use /amt refresh if you change the cutoff times",
      width = "full",
    },
    [5] = {
      type = "header",
      name = "Time and Date Format",
      width = "full",
    },
    [6] = {
      type = "description",
      title = "Guild Creation Date",
      text = AMT.exampleGuildFoundedDate .. "\nUse the date shown to choose the proper date format below.",
      width = "full",
    },
    [7] = {
      type = "dropdown",
      name = "Format",
      choices = AMT.dateFormats,
      choicesValues = AMT.dateFormatValues,
      getFunc = function() return AMT.savedData.dateTimeFormat end,
      setFunc = function(value) AMT.savedData.dateTimeFormat = value end,
      default = defaultData.dateTimeFormat,
    },
    [8] = {
      type = "description",
      title = "Note",
      text = "The date format is used to convert the founded date of the guild to an alternate format. This only effects the time used when a guild member doesn't have a join date.",
      width = "full",
    },
    [9] = {
      type = "header",
      name = "Export Options",
      width = "full",
    },
    [10] = {
      type = 'checkbox',
      name = "Export in Epoch Time",
      tooltip = "Export in Epoch Time that the game uses rather then convert the time stamp to text.",
      getFunc = function() return AMT.savedData.exportEpochTime end,
      setFunc = function(value)
        AMT.savedData.exportEpochTime = value
      end,
      default = amtDefaults.exportEpochTime,
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
  for guildNum = 1, GetNumGuilds() do
    local guildId = GetGuildId(guildNum)
    local guildName = GetGuildName(guildId)
    AMT.createGuild(guildName)
    for member = 1, GetNumGuildMembers(guildId), 1 do
      AMT:createUser(guildName, string.lower(GetGuildMemberInfo(guildId, member)))
    end
    if AMT.savedData["lastReceivedGeneralEventID"][guildId] == nil then AMT.savedData["lastReceivedGeneralEventID"][guildId] = "0" end
    if AMT.savedData["lastReceivedBankEventID"][guildId] == nil then AMT.savedData["lastReceivedBankEventID"][guildId] = "0" end
  end

  AMT:LibAddonInit()
  AMT:SetupListenerLibHistoire()
  AMT:KioskFlipListenerSetup()
  AMT:UpdatePlayerStatusLastSeen()

  EVENT_MANAGER:RegisterForEvent(AddonName, EVENT_GUILD_MEMBER_PLAYER_STATUS_CHANGED, OnStatusChanged)

  EVENT_MANAGER:UnregisterForEvent(AddonName, EVENT_ADD_ON_LOADED)
end

EVENT_MANAGER:RegisterForEvent(AddonName, EVENT_ADD_ON_LOADED, onAddOnLoaded)
