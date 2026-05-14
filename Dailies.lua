-------------------------------------------------------------------------
--
--	Copyright (c) 2019-2021 by Antoine Desmarets.
--	Cixi/Gaya of Remulos Oceanic / WoW Classic Horde
--  Xerseus of Pagle US / Calaclysm Classic Alliance
--
--	Dailies is distributed in the hope that it will be useful/entertaining
--	but WITHOUT ANY WARRANTY
--
-------------------------------------------------------------------------
-- Done in v044
-- - Updated to use C_GuildInfo.GuildRoster() instead of GuildRoster()

-------------------------------------------------------------------------
-- ADDON VARIABLES
-------------------------------------------------------------------------
local dllocal_addonName, Dailies = ... -- the addon name and a table scoped to all addon files referenced in the .toc is passed in by the wow client
local dllocal_addon = LibStub("AceAddon-3.0"):NewAddon(Dailies, dllocal_addonName, "AceConsole-3.0", "AceEvent-3.0", "AceComm-3.0")

local AceGUI = LibStub("AceGUI-3.0")
local _G = getfenv(0)

local dllocal_version = C_AddOns.GetAddOnMetadata(dllocal_addonName, "Version")
local dllocal_statusText = string.format("v%s by Zuwo@Dreamscythe +Xerseus +Komanchi +Timberwind", dllocal_version)	-- Default status text"
local dllocal_charKey = UnitName("player") .. "-" .. GetRealmName() -- Character unique name
local dllocal_prefix = "Dailies_Channel" -- used for addon chat communications
local dllocal_prefix_version = "Dailies_Version" -- used for addon version check

local dllocal_ldb = LibStub("LibDataBroker-1.1")
local dllocal_brokervalue = nil
local dllocal_brokerlabel = nil

local dllocal_filter_frame = nil -- filter sub menu

-- Frame variables
local dllocal_initial = true -- initial show of the frames
local dllocal_orderlist = {} -- List of dailies in order
local dllocal_tabgroup = nil -- tabgroup object 
local dllocal_tabkey = "todo" -- currently viewed tab

local dllocal_inGuild = false -- belong to a guild (for sending addon messages)
local dllocal_faction = "" -- to mark quest as one or the other or both

local dllocal_fullWidth = 760 -- width of the frame
local dllocal_fullHeight = 600 -- height of the frame

local dllocal_questTabs = {} -- all quests in their respective tabs
local dllocal_info_heading -- info panel Quest Heading
local dllocal_info_desc -- info panel Quest Desc
local dllocal_info_npc -- info panel Quest NPC
local dllocal_info_zone -- info panel Quest Zone/Subzone
local dllocal_info_count -- info panel Quest number of times done
local dllocal_info_inst -- related instance
local dllocal_tzdiff = 0 -- timezone difference in minutes (to check UTC reset times)

local dllocal_timer_handle -- handle for the UI reload timer, to be able to cancel while results are still coming

-- Frame variables
local dllocal_frame -- main frame

dllocal_group = {} -- quest metadata 
dllocal_reps = {} -- quest reputations
dllocal_repicons = {} -- reputation icons
dllocal_repfaction = {} -- reputation factions
dllocal_exclu = {} -- mutually exclusive quests
dllocal_ProfessionNames = {} -- profession names in all locales
dllocal_require = {}
dllocal_expac = {}

-- Thanks to Roadblock on Discord for this cool little snippet suggestion (and many other coding bits!)
-- I know you'll read this, thanks ;-)
local capture = _G.ERR_CHAT_PLAYER_NOT_FOUND_S:gsub("%%s","(.+)")
local function noPlayerFilter(self,event,msg,sender,...)
	local noPlayer = msg:match(capture)
	
	if noPlayer then
		return true
	else -- other system message just let it pass through
		return false, msg, sender, ...
	end
end

function Dailies:AddFilter()
	-- re-adding an already added filter is automatically ignored
	if not Dailies._filterActive then
		ChatFrame_AddMessageEventFilter("CHAT_MSG_SYSTEM", noPlayerFilter)
		Dailies._filterActive = true
	end
end

function Dailies:RemoveFilter()
	-- trying to remove a non-existent filter doesn't error no extra checks needed
	if Dailies._filterActive then
		ChatFrame_RemoveMessageEventFilter("CHAT_MSG_SYSTEM", noPlayerFilter)
		Dailies._filterActive = nil
	end
end

-------------------------------------------------------------------------
-- EVENT: Addon is Initialized
-------------------------------------------------------------------------
function Dailies:OnInitialize()
	Dailies:RegisterOptions()
	LibStub("AceConfigDialog-3.0"):AddToBlizOptions("Dailies"):SetParent(InterfaceOptionsFramePanelContainer)
	print("|cffff00ff[Dailies]|r "..dllocal_statusText)
end

-------------------------------------------------------------------------
-- EVENT: Addon is enabled
-------------------------------------------------------------------------
function Dailies:OnEnable()
	-- Called when the addon is enabled
	self:RegisterEvent("QUEST_DETAIL") --	get quest details from quest screen, even if not accepted
	self:RegisterEvent("QUEST_ACCEPTED") -- quest accept
	self:RegisterEvent("QUEST_TURNED_IN") --	quest completion
	self:RegisterEvent("UNIT_QUEST_LOG_CHANGED") -- used to check quest abandons
	self:RegisterEvent("QUEST_COMPLETE") -- used to trigger auto-complete (step 2)
	self:RegisterEvent("QUEST_PROGRESS") -- used to trigger auto-complete (step 1)
	self:RegisterEvent("GOSSIP_SHOW") -- used to trigger auto-complete and auto-accept
	
	if IsInGuild() then
		self:RegisterEvent("GUILD_ROSTER_UPDATE")
		dllocal_inGuild = true
	else
		dllocal_inGuild = false
		self:RegisterEvent("PLAYER_GUILD_UPDATE")
	end

	dllocal_tzdiff = time() - time(date("!*t")) -- pick up the timezone offset
	-- example tzdiff
	-- 36000 in Sydney (+10h)
	-- 34200 in Adelaide (+9.5h)
	
	C_ChatInfo.RegisterAddonMessagePrefix(dllocal_prefix)
	C_ChatInfo.RegisterAddonMessagePrefix(dllocal_prefix_version)
	Dailies:RegisterComm(dllocal_prefix)
	Dailies:RegisterComm(dllocal_prefix_version)

	Dailies_Data = Dailies_Data or {}

	-- adding the Toons group to make the saved data clearer
	if Dailies_Data.Toons == nil then 
		Dailies_Data.Toons = {} 

		-- moving any existing toon group to the new Toons group for backward compatibility
		for kt, t in pairs(Dailies_Data) do --all toons
			if string.find(kt, "-") then --key has a hyphen so it's a toon
				Dailies_Data.Toons[kt] = t -- add new
				Dailies_Data[kt] = nil -- remove old
			end
		end
	end

	Dailies_Data.Toons[dllocal_charKey] = Dailies_Data.Toons[dllocal_charKey] or {}
	Dailies_Data.Toons[dllocal_charKey].Quests = Dailies_Data.Toons[dllocal_charKey].Quests or {} 
	Dailies_Data.Toons[dllocal_charKey].TotalGold = Dailies_Data.Toons[dllocal_charKey].TotalGold or 0
	Dailies_Data.Toons[dllocal_charKey].TotalDailies = Dailies_Data.Toons[dllocal_charKey].TotalDailies or 0

	Dailies_Data.TotalGold = Dailies_Data.TotalGold or 0
	Dailies_Data.TotalDailies = Dailies_Data.TotalDailies or 0
	Dailies_Data.Quests = Dailies_Data.Quests or {}
	
	Dailies_Settings = Dailies_Settings or {}
	Dailies_Settings.showReceivedDailies = Dailies_Settings.showReceivedDailies or true
	Dailies_Settings.showQuestInfoPanel = Dailies_Settings.showQuestInfoPanel or true
	Dailies_Settings.showOnlyForKnownProfessions = Dailies_Settings.showOnlyForKnownProfessions or true
	
	Dailies_Settings.showQuestRewardTotal = Dailies_Settings.showQuestRewardTotal or true
	Dailies_Settings.autoAcceptQuests = Dailies_Settings.autoAcceptQuests or false
	Dailies_Settings.autoCompleteQuests = Dailies_Settings.autoCompleteQuests or false
	Dailies_Settings.showMinimapButton = Dailies_Settings.showMinimapButton or true
	Dailies_Settings.minimapButtonPosition = Dailies_Settings.minimapButtonPosition or {}
	
	if Dailies_Settings.runScanOnLogin == nil then Dailies_Settings.runScanOnLogin = true end
	Dailies_Settings.scanForAnyDailies = Dailies_Settings.scanForAnyDailies or false

	if Dailies_Settings.showSeasonalDailies == nil then Dailies_Settings.showSeasonalDailies = true end
	if Dailies_Settings.showTBCDailies == nil then Dailies_Settings.showTBCDailies = false end
	if Dailies_Settings.showWotLKDailies == nil then Dailies_Settings.showWotLKDailies = false end
	if Dailies_Settings.showCataDailies == nil then Dailies_Settings.showCataDailies = true end
	
	-- set defaults for existing dailies on new toons
	for kq, q in pairs(Dailies_Data.Quests) do 
		q.Text = q.Text:gsub("\n", "#N#") -- replace extra slashes
		q.Text = q.Text:gsub("\\r", "") 
		q.Text = q.Text:gsub("\\", "") 
		q.Text = q.Text:gsub("#N##N#", "#N#") 
		q.Text = q.Text:gsub("#N#", "\n") 

		Dailies_Data.Toons[dllocal_charKey].Quests[kq] = Dailies_Data.Toons[dllocal_charKey].Quests[kq] or {
			Ignored = false;
			Order = Dailies.count(Dailies_Data.Toons[dllocal_charKey].Quests) + 1; 
		} 

		if dllocal_temp[kq] == nil then 
			--add up the seen realm for non temp quests
			q.Seen = q.Seen or {} 
			q.Seen[GetRealmName()] = 1
		end
	end

	dllocal_faction, _ = UnitFactionGroup("player")

	-- find out what professions this toon has, as some quests are prof specific
	local profNames = dllocal_ProfessionNames[GetLocale()]
	local profNames_rev = tInvert(profNames)
	Dailies_Data.Toons[dllocal_charKey].Professions = {} -- force blank, to keep up to date
	
	for i = 1, GetNumSkillLines() do
		local name, _, _, skillRank = GetSkillLineInfo(i)
		
		if profNames_rev[name] then
			Dailies_Data.Toons[dllocal_charKey].Professions[profNames_rev[name]] = skillRank
		end
	end

	-- detect any daily quest that the player might already have in their log
	for i = 1, GetNumQuestLogEntries() do 
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
		frequency, id, startEvent, displayQuestID, isOnMap, hasLocalPOI,
		isTask, isStory = GetQuestLogTitle(i);

		if frequency > 1 then 
			--daily+
			if Dailies_Data.Quests[id] == nil then
				Dailies_Data.Quests[id] = {} 
				
				if Dailies_Settings.showReceivedDailies then
					print("|cffff00ff[Dailies]|r New daily quest detected: |cffffd100" .. title .. "|r")
				end

				--log this quest information
				Dailies_Data.Quests[id].Title = title or ""
				Dailies_Data.Quests[id].Text = "Placeholder. This will be populated next time you take the quest."
				Dailies_Data.Quests[id].Frequency = "Daily"
				Dailies_Data.Quests[id].Money = GetQuestLogRewardMoney(id) or 0
				Dailies_Data.Quests[id].Xp = 0 --GetQuestLogRewardXP(id) or 0 --not used, GetQuestLogRewardXP is deprecated
				Dailies_Data.Quests[id].Honor = GetQuestLogRewardHonor(id) or 0
				Dailies_Data.Quests[id].SubZone = "" -- will be populated later
				Dailies_Data.Quests[id].Zone = "" -- will be populated later
				Dailies_Data.Quests[id].Factions = {}
				Dailies_Data.Quests[id].Factions[dllocal_faction] = 1
				Dailies_Data.Quests[id].TodayUntil = nil
				Dailies_Data.Quests[id].NPC = "" -- will be populated later

				Dailies_Data.Toons[dllocal_charKey].Quests[id] = Dailies_Data.Toons[dllocal_charKey].Quests[id] or {
					Ignored = false;
					Order = Dailies.count(Dailies_Data.Toons[dllocal_charKey].Quests) + 1;
					TimesCompleted = 0;
				} 
			
				Dailies_Data.Quests[id].Seen = Dailies_Data.Quests[id].Seen or {}
				Dailies_Data.Quests[id].Seen[GetRealmName()] = 1
			end
		end
	end

	--- Guild info is not always ready at start. Waiting a couple seconds to retrieve it
	C_Timer.After(2, function()
		guildName, guildRankName, guildRankIndex = GetGuildInfo("player");
		
		if guildName ~= nil then
			dllocal_inGuild = true 
		end
	end)

	Dailies.ClassifyQuests()
	
	if Dailies_Settings.runScanOnLogin then 
		-- Call for getting today's dailies from peers
		C_Timer.After(9, function()	
			if dllocal_inGuild then 
				print("|cffff00ff[Dailies]|r Sending automatic request for "..(Dailies_Settings.scanForAnyDailies and "all" or "today's") .. " dailies.")
				Dailies:SendCommMessage(dllocal_prefix, (Dailies_Settings.scanForAnyDailies and "GET_ALL_DAILIES" or "GET_TODAYS_DAILIES"), "GUILD", "") 
			end
		end)
	end

	Dailies_Broker = dllocal_ldb:NewDataObject("Dailies_Broker", {
		type = "data source",
		label = "Dailies",
		text = "Click me!",
		icon = "Interface\\AddOns\\Dailies\\Images\\dailies",
		OnClick = function(self, button)
			if button == "LeftButton" then
				dllocal_frame = Dailies.getFrame()
			elseif button == "RightButton" then
				if Settings and Settings.OpenToCategory then
					Settings.OpenToCategory("Dailies")
				elseif InterfaceOptionsFrame_OpenToCategory then
					InterfaceOptionsFrame_OpenToCategory("Dailies")
					InterfaceOptionsFrame_OpenToCategory("Dailies")
				end
			end
		end,
		OnTooltipShow = function(tooltip)
			tooltip:AddLine("|cFFffffffDailies|r |cff808080v"..dllocal_version.."|r")

			if dllocal_brokerlabel ~= nil and dllocal_brokervalue ~= nil then
				tooltip:AddLine(" ")
				
				if dllocal_brokerlabel == "All Done!" then 
					tooltip:AddLine("|cffc0c0c0Next Step:|r None!")
				else
					tooltip:AddLine("|cffc0c0c0Next Step:|r |cffffffff" .. dllocal_brokervalue .. " the |r"..dllocal_brokerlabel.."|cffffffff quest|r.")
				end
				
				Dailies_Broker.text = dllocal_brokervalue .. " " .. dllocal_brokerlabel
			end

			tooltip:AddLine(" ")
			tooltip:AddLine("|cffffd100Left Click |rOpen quest list\n|cffffd100Right Click |rOpen settings", 0.2, 1, 0.2)
		end,
	})

	if Dailies_Broker then
		Dailies_Broker.text = dllocal_brokervalue .. " " .. dllocal_brokerlabel
	end

	Dailies:RegisterMinimapButton()
end

-------------------------------------------------------------------------
-- EVENT: Addon is disabled
-------------------------------------------------------------------------
function Dailies:OnDisable()
	-- Called when the addon is disabled
	print("|cffff00ff[Dailies]|r Addon disabled")
end

function Dailies:QUEST_DETAIL(event)
	local id = GetQuestID()

	if QuestIsDaily() == true then 
		if Dailies_Data.Quests[id] == nil then
			Dailies_Data.Quests[id] = {} 
			
			if Dailies_Settings.showReceivedDailies then
				print("|cffff00ff[Dailies]|r New daily quest detected: |cffffd100" .. GetTitleText() .. "|r")
			end
		end
 
		--log this quest information
		Dailies_Data.Quests[id].Title = GetTitleText()
		Dailies_Data.Quests[id].Text = GetObjectiveText()
		Dailies_Data.Quests[id].Frequency = "Daily"
		Dailies_Data.Quests[id].Money = GetRewardMoney()
		Dailies_Data.Quests[id].Xp = GetRewardXP()
		Dailies_Data.Quests[id].Honor = GetRewardHonor()
		Dailies_Data.Quests[id].SubZone = GetSubZoneText()
		Dailies_Data.Quests[id].Zone = GetZoneText()

		Dailies_Data.Quests[id].Factions = Dailies_Data.Quests[id].Factions or {}
		
		Dailies_Data.Quests[id].Factions[dllocal_faction] = 1
		Dailies_Data.Quests[id].TodayUntil = Dailies.DailyResetTime()
		Dailies_Data.Quests[id].NPC = UnitName("target")
 
		Dailies_Data.Toons[dllocal_charKey].Quests[id] = Dailies_Data.Toons[dllocal_charKey].Quests[id] or {
			Ignored = false ;
			Order = Dailies.count(Dailies_Data.Toons[dllocal_charKey].Quests) + 1;
			TimesCompleted = 0;
		} 

		Dailies_Data.Quests[id].Seen = Dailies_Data.Quests[id].Seen or {}
		Dailies_Data.Quests[id].Seen[GetRealmName()] = 1

		Dailies.MakeGroupDaily(id)
		
		if dllocal_frame and dllocal_frame:IsVisible() then
			Dailies.ShowTabContent()
		end

		-- spam the info
		local ser = id.."|"..Dailies.serialize(Dailies_Data.Quests[id]):gsub(" = ", "="):gsub(" ", ""):gsub(" }", "}")
		if dllocal_inGuild then 
			Dailies:SendCommMessage(dllocal_prefix, ser, "GUILD", "")
		end

		-- auto-accept if needed
		if dllocal_questTabs.ToDo[id] and Dailies_Settings.autoAcceptQuests then 
			AcceptQuest()
		end

		Dailies.ClassifyQuests()
	end
end

function Dailies:QUEST_ACCEPTED(event, logid, id)
	if Dailies_Data.Quests[id] then 
		Dailies_Data.Toons[dllocal_charKey].Quests[id] = Dailies_Data.Toons[dllocal_charKey].Quests[id] or {}
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Accepted = time()
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Completed = nil
		Dailies_Data.Toons[dllocal_charKey].Quests[id].TimesCompleted = Dailies_Data.Toons[dllocal_charKey].Quests[id].TimesCompleted or 0
		
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration or {
			Current = nil;
			Last = nil;
			Fastest = nil;
			Slowest = nil;	
		}
		
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Last = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current 
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current = nil

		-- need async otherwise the quest is not detected as completed
		C_Timer.After(1, function()	
			Dailies.ClassifyQuests() 
			
			if dllocal_frame and dllocal_frame:IsVisible() then
				Dailies.ShowTabContent()
			end
		end) 
	end
end

function Dailies:QUEST_TURNED_IN(event, id, xp, copper)
	if Dailies_Data.Toons[dllocal_charKey].Quests[id] ~= nil then 
		Dailies_Data.Toons[dllocal_charKey].Quests[id].Completed = time()
		Dailies_Data.Toons[dllocal_charKey].Quests[id].TimesCompleted = (Dailies_Data.Toons[dllocal_charKey].Quests[id].TimesCompleted or 0) + 1 

		Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration or {
			Current = nil;
			Last = nil;
			Fastest = nil;
			Slowest = nil;
		} 

		if Dailies_Data.Toons[dllocal_charKey].Quests[id].Completed and Dailies_Data.Toons[dllocal_charKey].Quests[id].Accepted then 
			Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current = Dailies_Data.Toons[dllocal_charKey].Quests[id].Completed - Dailies_Data.Toons[dllocal_charKey].Quests[id].Accepted
		end
		
		if Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Fastest == nil or Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current < Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Fastest then 
			Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Fastest = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current
		end
		
		if Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Slowest == nil or Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current > Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Slowest then 
			Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Slowest = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration.Current
		end

		Dailies_Data.Toons[dllocal_charKey].TotalGold = (Dailies_Data.Toons[dllocal_charKey].TotalGold or 0) + Dailies_Data.Quests[id].Money 
		Dailies_Data.Toons[dllocal_charKey].TotalDailies = (Dailies_Data.Toons[dllocal_charKey].TotalDailies or 0) + 1
		Dailies_Data.TotalGold = (Dailies_Data.TotalGold or 0) + Dailies_Data.Quests[id].Money 
		Dailies_Data.TotalDailies = (Dailies_Data.TotalDailies or 0) + 1

		-- need async otherwise the quest is not detected as completed
		C_Timer.After(1, function()	
			Dailies.ClassifyQuests() 

			if dllocal_frame and dllocal_frame:IsVisible() then
				Dailies.ShowTabContent()
			end
		end) 
	end
end

function Dailies:QUEST_COMPLETE(event)
	local id = GetQuestID()

	-- auto-complete if needed
	if dllocal_questTabs.ToDo[id] and Dailies_Settings.autoCompleteQuests then 
		QuestRewardCompleteButton_OnClick()
	end

	-- need async otherwise the quest is not detected as completed
	C_Timer.After(1, function()	
		Dailies.ClassifyQuests() 
		
		if dllocal_frame and dllocal_frame:IsVisible() then
			Dailies.ShowTabContent()
		end
	end)
end

function Dailies:QUEST_PROGRESS(event)
	local id = GetQuestID()

	-- auto-complete if needed
	if dllocal_questTabs.ToDo[id] and Dailies_Settings.autoCompleteQuests then 
		CompleteQuest()
	end
end

function Dailies:GOSSIP_SHOW(event)
	-- auto accepts
	if Dailies_Settings.autoAcceptQuests then 
		local arg = C_GossipInfo.GetAvailableQuests();
		local ind = 1
		while(arg[ind]) do
			--check name against to do list
			local qq = {};
			qq.title = arg[ind].title; -- name
			qq.freq = arg[ind].frequency;	-- freq
			qq.questID = arg[ind].questID

			if qq.freq == 1 then --is a daily
				for ktd, td in pairs(dllocal_questTabs.ToDo) do 
					if Dailies_Data.Quests[ktd] and Dailies_Data.Quests[ktd].Title == qq.title then
						C_GossipInfo.SelectAvailableQuest(qq.questID)
					end
				end
			end

			ind = ind + 1	-- quest index
		end
	end

	-- auto completes
	if Dailies_Settings.autoCompleteQuests then 
		local arg = C_GossipInfo.GetActiveQuests();
		local ind = 1
		while(arg[ind]) do
			--check name against to do list
			local qq = {};
			qq.title = arg[ind].title; -- name
			qq.questID = arg[ind].questID

			for ktd, td in pairs(dllocal_questTabs.ToDo) do 
				if Dailies_Data.Quests[ktd] and Dailies_Data.Quests[ktd].Title == qq.title then
					if Dailies.ReadyToComplete(ktd) then 
						C_GossipInfo.SelectActiveQuest(qq.questID)
					end
				end	
			end

			ind = ind + 1	-- quest index
		end
	end
end

function Dailies:UNIT_QUEST_LOG_CHANGED(event, unit)
	if dllocal_frame and dllocal_frame:IsVisible() then
		C_Timer.After(0.5, function()
			Dailies.ShowTabContent()
		end) -- slight delay for the quest to be abandonned *before* the log refresh
	end
end

function Dailies:GUILD_ROSTER_UPDATE(event, canRequestUpdate)
	self._guildOnlineCache = self._guildOnlineCache or {}
	if canRequestUpdate then
		C_GuildInfo.GuildRoster()
	end
	
	for i = 1, GetNumGuildMembers(true) do
		local fullName, rank, rankIndex, level, class, zone, note, officernote, online = GetGuildRosterInfo(i)
		if fullName and fullName ~= _G.UNKNOWNOBJECT then
			self._guildOnlineCache[fullName] = online and true or nil
		end
	end
end

function Dailies:PLAYER_GUILD_UPDATE(event, unit)
	if unit and UnitIsUnit(unit,"player") then
		if IsInGuild() then
			dllocal_inGuild = true
			self:RegisterEvent("GUILD_ROSTER_UPDATE")
		else
			dllocal_inGuild = false
		end
	end
end

function Dailies.DailyResetTime()
	local region = GetCurrentRegion()
	local reset

	if region == 1 then
		reset = 15 -- US / Oceania / South America
	elseif region == 2 then
		reset = 23 -- Korea
	elseif region == 3 then
		reset = 7 -- Europe / Russia
	elseif region == 4 then
		reset = 23 -- Taiwan
	elseif region == 5 then
		reset = 23 -- China
	else
		reset = 15
	end
	
	local time_utc = date("!*t")
	
	-- next day if we're just past the reset time
	if time_utc.hour * 60 + time_utc.min > reset * 60 then
		time_utc.day = time_utc.day + 1
	end
	
	time_utc.hour = reset
	time_utc.min = 0
	time_utc.sec = 0
	
	return time(time_utc) + dllocal_tzdiff
end

-------------------------------------------------------------------------
-- Create the Main UI Frame
-------------------------------------------------------------------------
function Dailies.getFrame()
	-- if view already exists, just return it
	if dllocal_frame then 
		Dailies.ShowTabContent()
		dllocal_frame:Show()
		dllocal_filter_frame.frame:Show()
		return dllocal_frame 
	end

	dllocal_frame = AceGUI:Create("Frame", "DailiesFrame")
	dllocal_frame:SetTitle(" Dailies")
	dllocal_frame:SetStatusText(dllocal_statusText)
	dllocal_frame:SetHeight(dllocal_fullHeight)
	dllocal_frame:SetWidth(dllocal_fullWidth)

	if dllocal_frame.frame.SetResizeBounds then
		dllocal_frame.frame:SetResizeBounds(dllocal_fullWidth, dllocal_fullHeight)
	else 
		dllocal_frame.frame:SetMinResize(dllocal_fullWidth, dllocal_fullHeight)
		dllocal_frame.frame:SetMaxResize(dllocal_fullWidth, 3000)
	end
	
	dllocal_frame:SetLayout("Flow")

	-- Register the global variable `Dailies_MainFrame` as a "special frame"
	-- so that it is closed when the escape key is pressed.
	_G["Dailies_MainFrame"] = dllocal_frame.frame
	tinsert(UISpecialFrames, "Dailies_MainFrame")

	dllocal_frame.frame:SetFrameStrata("HIGH")

	-- Hacking into the Ace3 frame to reduce the size of the statusbox, to allow us room for other buttons
	local closebutton, statusbg, _, _, _, _, _ = dllocal_frame.content.obj.frame:GetChildren()
	statusbg:ClearAllPoints()
	statusbg:SetPoint("BOTTOMLEFT", 15, 14) -- taken from AceGUIContainer-Frame.lua
	statusbg:SetPoint("BOTTOMRIGHT", -398, 14) -- taken from AceGUIContainer-Frame.lua, modified from -132
	closebutton:SetWidth(80)

	-- SETTINGS BUTTON (gear icon)
	local settingsbutton = CreateFrame("Button", "Dailies_SettingsButton", dllocal_frame.content.obj.frame)
	settingsbutton:SetPoint("TOPRIGHT", dllocal_frame.content.obj.frame, "TOPRIGHT", -18, -13)
	settingsbutton:SetFrameStrata("DIALOG")
	settingsbutton:SetHeight(20)
	settingsbutton:SetWidth(20)
	settingsbutton:SetNormalTexture("Interface\\Buttons\\UI-OptionsButton")
	settingsbutton:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
	settingsbutton:SetScript("OnEnter", function(self)
		dllocal_frame:SetStatusText("Open Dailies settings.")
		GameTooltip:SetOwner(self, "ANCHOR_TOPRIGHT")
		GameTooltip:SetText("Settings")
		GameTooltip:Show()
	end)
	settingsbutton:SetScript("OnLeave", function()
		dllocal_frame:SetStatusText(dllocal_statusText)
		GameTooltip:Hide()
	end)
	settingsbutton:SetScript("OnClick", function()
		if Settings and Settings.OpenToCategory then
			Settings.OpenToCategory("Dailies")
		elseif InterfaceOptionsFrame_OpenToCategory then
			InterfaceOptionsFrame_OpenToCategory("Dailies")
			InterfaceOptionsFrame_OpenToCategory("Dailies")
		end
	end)

	-- Tabs
	dllocal_tabgroup = AceGUI:Create("TabGroup")
	dllocal_tabgroup:SetTabs({{value="todo", text="To Do"}, {value="completed", text="Completed"}, {value="ignored", text="Ignored"}, {value="all", text="All Dailies"}, {value="stats", text="Statistics"}})
	dllocal_tabgroup:SelectTab("todo")
	dllocal_tabgroup:SetLayout("flow")
	dllocal_tabgroup:SetFullWidth(true)
	dllocal_tabgroup:SetFullHeight(true)
	dllocal_tabgroup:SetCallback("OnGroupSelected", function(source, event, tabkey)
		dllocal_tabkey = tabkey
		Dailies.ShowTabContent()
	end)
	dllocal_frame:AddChild(dllocal_tabgroup)
	
	-- SCAN BUTTON
	local scanbutton = CreateFrame("Button", "Dailies_ScanButton", dllocal_frame.content.obj.frame, "UIPanelButtonTemplate")
	scanbutton:SetPoint("BOTTOMRIGHT", -110, 17)
	scanbutton:SetFrameStrata("DIALOG")
	scanbutton:SetHeight(20)
	scanbutton:SetWidth(80)
	scanbutton:SetText("Scan")
	
	scanbutton:SetScript("OnEnter", function()
		dllocal_frame:SetStatusText("Scan guildies for dailies.")
	end)
	
	scanbutton:SetScript("OnLeave", function()
		dllocal_frame:SetStatusText(dllocal_statusText)
	end)
	
	scanbutton:SetScript("OnClick", function()
		if dllocal_inGuild then 
			Dailies:SendCommMessage(dllocal_prefix, (Dailies_Settings.scanForAnyDailies and "GET_ALL_DAILIES" or "GET_TODAYS_DAILIES"), "GUILD", "") 
		end
		
		print("|cffff00ff[Dailies]|r Sending request for "..(Dailies_Settings.scanForAnyDailies and "all" or "today's") .. " dailies.")
	end)

	-- FILTER DROPDOWN
	dllocal_filter_frame = AceGUI:Create("Dropdown")
	dllocal_filter_frame:SetWidth(200)
	dllocal_filter_frame.frame:SetFrameStrata("DIALOG")
	dllocal_filter_frame:SetPoint("TOPRIGHT", scanbutton,"TOPLEFT", -5, 2)
	dllocal_filter_frame:AddItem(0, "|TInterface\\AddOns\\Dailies\\Images\\ignored:16|t No reputation filter")

	if dllocal_repicons then 
		for kr, r in Dailies.spairs(dllocal_repicons, function(t,a,b) 
			local namea = GetFactionInfoByID(a);
			local nameb = GetFactionInfoByID(b);

			if namea ~= nil and nameb ~= nil then
				return namea < nameb
			end
		end) do --sorted reps
                        if      (r.expac == 0) or
                                (Dailies_Settings.showTBCDailies and r.expac == 2) or
                                (Dailies_Settings.showWotLKDailies and r.expac == 3) or 
                                (Dailies_Settings.showCataDailies and r.expac == 4) then 

                                local name, _, _, _, _, earnedValue = GetFactionInfoByID(kr)
                                
                                if name ~= nil then 
                                        dllocal_filter_frame:AddItem(kr, "|T" .. r.icon .. ":16|t " .. name)
                                end 
                        end
		end
	end

	dllocal_filter_frame:SetCallback("OnValueChanged", function(choice) 
		if choice:GetValue() == 0 then
			Dailies_Data.Toons[dllocal_charKey].RepFilter = nil 
		else
			Dailies_Data.Toons[dllocal_charKey].RepFilter = choice:GetValue() 
		end
	
		Dailies.ShowTabContent()
	end )
	if Dailies_Data.Toons[dllocal_charKey].RepFilter == nil then
		dllocal_filter_frame:SetValue(0) 
	else
		dllocal_filter_frame:SetValue(Dailies_Data.Toons[dllocal_charKey].RepFilter) 
	end

	-- Register the global variable `Dailies_MainFrame` as a "special frame"
	-- so that it is closed when the escape key is pressed.
	_G["Dailies_RepFilterFrame"] = dllocal_filter_frame.frame
	tinsert(UISpecialFrames, "Dailies_RepFilterFrame")

	closebutton:SetScript("OnClick", function() 
		dllocal_filter_frame.frame:Hide()	
		dllocal_frame:Hide()
	end)

	Dailies.ShowTabContent()
	dllocal_frame:Show()
	dllocal_initial = false
	return dllocal_frame
end

function Dailies.ShowTabContent()
	if dllocal_tabgroup ~= nil then 
		dllocal_tabgroup:ReleaseChildren()

		if dllocal_tabkey == "stats" then 
			local one_q = 0
			local one_g = 0
			local all_q = 0
			local all_g = 0
			local one_fav = ""
			local one_cnt = 0
			local all_fav = ""
			local all_cnt = 0
			local one_fastest_name = ""
			local one_fastest_val = 999999999
			local all_fastest_name = ""
			local all_fastest_val = 999999999

			for kt, t in pairs(Dailies_Data.Toons) do --all toons
				for kd, d in pairs(t.Quests) do --all dailies
					if Dailies_Data.Quests[kd] then 
						if d.TimesCompleted and d.TimesCompleted > 0 then 
							all_q = all_q + d.TimesCompleted
							
							if Dailies_Data.Quests[kd] and Dailies_Data.Quests[kd].Money then 
								all_g = all_g + ( d.TimesCompleted * Dailies_Data.Quests[kd].Money)
							end
 
							if d.TimesCompleted > all_cnt then 
								all_cnt = d.TimesCompleted
								all_fav = Dailies_Data.Quests[kd].Title
							end
							
							if d.Duration and d.Duration.Fastest and d.Duration.Fastest < all_fastest_val then 
								all_fastest_val = d.Duration.Fastest
								all_fastest_name = Dailies_Data.Quests[kd].Title
							end

							--toon stats
							if kt == dllocal_charKey then 
								one_q = one_q + d.TimesCompleted
								
								if Dailies_Data.Quests[kd] and Dailies_Data.Quests[kd].Money then 
									one_g = one_g + ( d.TimesCompleted * Dailies_Data.Quests[kd].Money)
								end
 
								if d.TimesCompleted > one_cnt then 
									one_cnt = d.TimesCompleted
									one_fav = Dailies_Data.Quests[kd].Title
								end
 
								if d.Duration and d.Duration.Fastest and d.Duration.Fastest < one_fastest_val then 
									one_fastest_val = d.Duration.Fastest
									one_fastest_name = Dailies_Data.Quests[kd].Title
								end
							end 
						end
					end
				end
			end

			local stats = AceGUI:Create("SimpleGroup")
			stats:SetFullWidth(true)
			stats:SetAutoAdjustHeight(true)
			stats:SetLayout("Flow")

			local meh = AceGUI:Create("Label")
			meh:SetText("\n Here's a few meaningless statistics collected about your dailies")
			meh:SetFullWidth(true)
			meh:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(meh)

			local spacer = AceGUI:Create("Label")
			spacer:SetText(" ")
			spacer:SetFullWidth(true)
			spacer:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(spacer)

			local oneh = AceGUI:Create("Heading")
			oneh:SetText("|cffffffff" .. dllocal_charKey .. "|r")
			oneh:SetFullWidth(true)
			stats:AddChild(oneh)

			local oneq = AceGUI:Create("Label")
			oneq:SetText("\n Total daily quests completed: |cffffd100" .. one_q .. "|r")
			oneq:SetFullWidth(true)
			oneq:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(oneq)

			local oneg = AceGUI:Create("Label")
			oneg:SetText("\n Total gold from daily quests: " .. GetMoneyString(one_g, true))
			oneg:SetFullWidth(true)
			oneg:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(oneg)

			local onem = AceGUI:Create("Label")
			
			if one_cnt > 0 then 
				onem:SetText("\n Most repeated daily: |cffffd100" .. one_fav .. "|r (" .. one_cnt .. " times)")
			else
				onem:SetText("\n Most repeated daily: |cffffd100-|r")
			end
			
			onem:SetFullWidth(true)
			onem:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(onem)

			local onef = AceGUI:Create("Label")
			
			if one_fastest_name ~= "" then 
				onef:SetText("\n Fastest completed daily: |cffffd100" .. one_fastest_name .. "|r (" .. Dailies.formatTime(one_fastest_val) .. ")")
			else
				onef:SetText("\n Fastest completed daily: |cffffd100-|r")
			end
			
			onef:SetFullWidth(true)
			onef:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(onef)
			
			local spacer = AceGUI:Create("Label")
			spacer:SetText(" ")
			spacer:SetFullWidth(true)
			spacer:SetFont(GameFontNormal:GetFont(), 12)
			stats:AddChild(spacer)

			local clearOne = AceGUI:Create("Button")
			clearOne:SetText("Reset data for this toon")
			clearOne:SetCallback("OnClick", function() 
			
			for kq, q in pairs(Dailies_Data.Toons[dllocal_charKey].Quests) do 
				q.TimesCompleted = nil
			end
 
			Dailies.ShowTabContent()
		end)
 
		stats:AddChild(clearOne)

		local spacer = AceGUI:Create("Label")
		spacer:SetText(" ")
		spacer:SetFullWidth(true)
		spacer:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(spacer)

		local allh = AceGUI:Create("Heading")
		allh:SetText("|cffffffffAcross all characters|r")
		allh:SetFullWidth(true)
		stats:AddChild(allh)

		local allq = AceGUI:Create("Label")
		allq:SetText("\n Total daily quests completed: |cffffd100" .. all_q .. "|r")
		allq:SetFullWidth(true)
		allq:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(allq)

		local allg = AceGUI:Create("Label")
		allg:SetText("\n Total gold from daily quests: " .. GetMoneyString(all_g, false))
		allg:SetFullWidth(true)
		allg:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(allg)

		local allm = AceGUI:Create("Label")
	
		if all_cnt > 0 then 
			allm:SetText("\n Most repeated daily: |cffffd100" .. all_fav .. "|r (" .. all_cnt .. " times)")
		else
			allm:SetText("\n Most repeated daily: |cffffd100-|r")
		end
 
		allm:SetFullWidth(true)
		allm:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(allm)

		local allf = AceGUI:Create("Label")
		
		if all_fastest_name ~= "" then 
			allf:SetText("\n Fastest completed daily: |cffffd100" .. all_fastest_name .. "|r (" .. Dailies.formatTime(all_fastest_val) .. ")")
		else
			allf:SetText("\n Fastest completed daily: |cffffd100-|r")
		end
		
		allf:SetFullWidth(true)
		allf:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(allf)

		local spacer = AceGUI:Create("Label")
		spacer:SetText(" ")
		spacer:SetFullWidth(true)
		spacer:SetFont(GameFontNormal:GetFont(), 12)
		stats:AddChild(spacer)

		local clearAll = AceGUI:Create("Button")
		clearAll:SetText("Reset all data")
		clearAll:SetCallback("OnClick", function() 
			for kt, t in pairs(Dailies_Data.Toons) do 
				for kq, q in pairs(t.Quests) do 
					q.TimesCompleted = nil
				end
			end
			
			Dailies.ShowTabContent()
		end)
	
		stats:AddChild(clearAll)
		dllocal_tabgroup:AddChild(stats)
	else
		local showTotal = Dailies_Settings.showQuestRewardTotal
	
		if dllocal_tabkey == "all" then
			showTotal = false
		end -- removing totals from the ALL tab, as they are wrong (all dungeon dailies counted for example)

		Dailies.ClassifyQuests()
 
		local scroll = AceGUI:Create("ScrollFrame")
		scroll:SetLayout("Flow")
		scroll:SetFullWidth(true)
		local hh = 0
 
		if Dailies_Settings.showQuestInfoPanel then 
			hh = hh + 130 -- 130 is the size of the info panel
		end

		if showTotal then 
			hh = hh + 45 -- 45 is the size of the info panel
		end

		scroll.frame:SetScript("OnUpdate", function()
			-- auto resize scroll zone when frame is resized
			if Dailies_Settings.showQuestInfoPanel or showTotal then 
				scroll:SetHeight(dllocal_frame.frame:GetHeight() - 120 - hh) --120 is the offset for the frame
			end
		end)

		if hh ~= 0 then 
			scroll:SetHeight(dllocal_frame.frame:GetHeight() - 120 - hh) --120 is the offset for the frame
			scroll:SetAutoAdjustHeight(false)
		else
			scroll:SetFullHeight(true)
		end

		dllocal_tabgroup:AddChild(scroll)

		local count = 0
		dllocal_orderlist = {}

		local completedGroups = {} -- used to not repeat completed quests from the same group
		local listedGroups = {} -- used to not repeat completed quests from the same group
 
		local list = dllocal_questTabs.ToDo
	
		if dllocal_tabkey == "all" then
			list = dllocal_questTabs.All
		end 
 
		if dllocal_tabkey == "completed" then
			list = dllocal_questTabs.Completed
		end 
	
		if dllocal_tabkey == "ignored" then
			list = dllocal_questTabs.Ignored
		end 

		local totalGold = 0
		local totalHonor = 0
		local totalReps = {}
		local previousHeader = ""
		local fullday = 24 * 60 * 60

		for kq, ql in Dailies.spairs(list, function(t,a,b) 
			if dllocal_tabkey == "all" then 
				return (dllocal_group[a] and dllocal_group[a].group or "ZZZ") .. "_" ..
				(Dailies_Data.Quests[a].Zone or "YYY") .. "_" ..
				Dailies_Data.Quests[a].Title < (dllocal_group[b] and dllocal_group[b].group or "ZZZ") .. "_" ..
				(Dailies_Data.Quests[b].Zone or "YYY") .. "_" .. Dailies_Data.Quests[b].Title
			else 
				return Dailies_Data.Toons[dllocal_charKey].Quests[a].Order < Dailies_Data.Toons[dllocal_charKey].Quests[b].Order 
			end
		end) do --all dailies
			local q = Dailies_Data.Quests[kq]
			local expac = dllocal_expac[q.Zone]
 
			if (Dailies_Settings.showTBCDailies and expac == 2) or
			   (Dailies_Settings.showWotLKDailies and expac == 3) or 
                           (Dailies_Settings.showCataDailies and expac == 4) then 

				if dllocal_seasonal[kq] == nil or (Dailies_Settings.showSeasonalDailies and dllocal_seasonal[kq] ~= nil) then 
					local header = string.upper(dllocal_group[kq] and dllocal_group[kq].group or "")
				
					if header == "" then 
						header = string.upper(q.Zone or "")
					end
 
					if header == "" then
						header = "OTHER (Missing Zone)"
					end

					-- only mark as completed those that actually got completed in the group.
					-- by default the API marks all quests of a group as completed together, so we need to check our data to know which one.
					local completed = C_QuestLog.IsQuestFlaggedCompleted(kq)

					-- add to listed groups to avoid the generic group line
					if completed and dllocal_group[kq] then
						listedGroups[dllocal_group[kq].group] = true
					end

					if Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored and dllocal_group[kq] then
						listedGroups[dllocal_group[kq].group] = true
					end

					dllocal_orderlist[Dailies.count(dllocal_orderlist) + 1] = kq

					-- Check if we already have the quest in our log
					local alreadyHaveIt = Dailies.AlreadyHaveQuest(kq)

					-- Now check if that quest if part of a group where you can only have 1 of the group at the time
					-- for example the fishing daily, or the cooking daily, or the daily dungeon

					-- logic to follow:
					-- - if you already have the quest, then show that.
					-- - if it is the daily, then show it UNLESS we already have one of that group in our log.
					-- - if the quest is not daily and not already in log, skip it
					-- - if we've done one from the group, skip all and put a placeholder with the group name
					-- - if we know the daily and it's not the one we have, then add an alternative line to say this quest can be picked up instead if needed
					local todaysDaily = true

					-- if a group, check if it's todays				
					if q.TodayUntil == nil then 
						todaysDaily = false
					elseif (time(date("!*t")) + dllocal_tzdiff) > q.TodayUntil then
						q.TodayUntil = nil
						todaysDaily = false 
					end

					local haveAnotherAlready = false
			
					if dllocal_group[kq] then -- part of a group
						for kq2, q2 in pairs(dllocal_group) do 
							if dllocal_group[kq2].group == dllocal_group[kq].group and kq2 ~= kq then
								if Dailies.AlreadyHaveQuest(kq2) then 
									haveAnotherAlready = true 
								end
							end
						end
					end

					-- add to listed groups to avoid the generic group line
					if dllocal_group[kq] and listedGroups[dllocal_group[kq].group] == nil then
						listedGroups[dllocal_group[kq].group] = true
					end
 
					if header ~= previousHeader and dllocal_tabkey == "all" then 
						local head = AceGUI:Create("Label")
					
						if previousHeader ~= "" then 
							head:SetText("\n" .. header)
						else
							head:SetText(header)
						end -- display the header, add a blank row first if not the first header
 
						head:SetFullWidth(true)
						head:SetJustifyH("LEFT")
						head:SetFont(GameFontNormal:GetFont(), 12)
 
						scroll:AddChild(head)
					end 

					--Compact view
					local tit = "|cffffd100" .. q.Title .. "|r"
					local status = "|TInterface\\AddOns\\Dailies\\Images\\available:16|t"
					local desc = "This quest is available for you to pick up."
 
					if alreadyHaveIt then 
						if Dailies.ReadyToComplete(kq) then 
							status = "|TInterface\\AddOns\\Dailies\\Images\\selecteddone:16|t"; 
							desc = "This quest is ready to turn in."
							tit = "|cff00ff00" .. q.Title .. "|r" -- green is quest is ready to turn in 
						else
							status = "|TInterface\\AddOns\\Dailies\\Images\\selected:16|t"; 
							desc = "You have that quest in your quest log." 
						end
					end
				
					if completed then
						status = "|TInterface\\AddOns\\Dailies\\Images\\completed:16|t"; desc = "You have completed this quest today"
					end 
 
					if Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored then
						status = "|TInterface\\AddOns\\Dailies\\Images\\ignored:16|t"
						desc = "You are ignoring this quest"
					end 

					-- check if any other toon has already completed this quest and add them to the tool tip
					local otherCompleted = ""

					for kt, t in pairs(Dailies_Data.Toons) do --all toons
						if t.Quests[kq] and t.Quests[kq].Completed ~= nil then 
							if q.TodayUntil ~= nil then 
								if t.Quests[kq].Completed > q.TodayUntil - fullday then 
									otherCompleted = otherCompleted .. "\n" .. " |TInterface\\AddOns\\Dailies\\Images\\completed:16|t " .. kt
								end
							end
						end 
					end

					local quest = AceGUI:Create("SimpleGroup")
					quest:SetFullWidth(true)
					quest:SetAutoAdjustHeight(true)
					quest:SetLayout("Flow")
					local showprof = true
					
					if dllocal_group[kq] then 
						if dllocal_group[kq].short then 
							tit = tit .. "|cff808080 - |r|cffffffff" .. dllocal_group[kq].short .. "|r"
						end

						if dllocal_tabkey ~= "all" then 
							tit = tit .. "|cff808080 - " .. dllocal_group[kq].group .. "|r"
						end
						
						showprof = false
					end

					if dllocal_prof[kq] and showprof then 
						if dllocal_ProfessionNames[GetLocale()] then 
							if dllocal_ProfessionNames[GetLocale()][dllocal_prof[kq]] then 
								tit = tit .. "|cff808080 - " .. dllocal_ProfessionNames[GetLocale()][dllocal_prof[kq]] .. "|r"
							end
						end
					end

					if dllocal_seasonal[kq] then 
						tit = tit .. "|cff808080 - Seasonal|r"
					end

					local title = AceGUI:Create("InteractiveLabel")
					title:SetText(status.." "..tit)
					
					if dllocal_tabkey ~= "all" then 
						title:SetWidth(480)
					else
						title:SetWidth(480 +20 +20) --to make up for the arrows being hidden
					end
				
					title:SetJustifyH("LEFT")
					title:SetFont(GameFontNormal:GetFont(), 12)

					title:SetCallback("OnEnter", function() 
						GameTooltip:SetOwner(title.frame,"ANCHOR_NONE")
						GameTooltip:SetPoint("TOPLEFT", title.frame,"BOTTOMLEFT", 20, -8)
						local dd = desc
				
						if Dailies_Settings.showQuestInfoPanel then
							dd = dd .. "\nClick for more info."
						end

						if otherCompleted ~= "" then
							dd = dd .. "\n\n|cffffffffAlready completed by:\n"..otherCompleted.."|r"
						end
					
						GameTooltip:SetText("|cffa0a0a0" .. dd .. "|r")
					end)

					title:SetCallback("OnClick", function() 
						if Dailies_Settings.showQuestInfoPanel then 						
							if q.NPC and q.NPC ~= "" then 
								dllocal_info_npc:SetText("Quest giver: |cffffd100" .. q.NPC .. "|r") 
							else
								dllocal_info_npc:SetText("Quest giver: |cffffd100-|r") 
							end 
							
							if q.Zone and q.Zone ~= "" then
								dllocal_info_zone:SetText(q.Zone)
							else
								dllocal_info_zone:SetText("- ")
							end

							local timesCompleted = 0
							
							if Dailies_Data.Toons[dllocal_charKey].Quests[kq].TimesCompleted then 
								timesCompleted = Dailies_Data.Toons[dllocal_charKey].Quests[kq].TimesCompleted
							end
				
							dllocal_info_count:SetText("Times completed: |cffffd100" .. timesCompleted.."|r")
				
							if q.SubZone and q.SubZone ~= "" then
								dllocal_info_coords:SetText(q.SubZone)
							else
								dllocal_info_coords:SetText("- ")
							end
				
							if q.Text then 
								dllocal_info_desc:SetText("\n|cffa0a0a0" .. q.Text .. "|r"); 
								dllocal_info_desc:SetJustifyH("LEFT") 
							end
				
							if q.Title then
								dllocal_info_heading:SetText("|cffffffff" .. q.Title .. "|r")
							end

							if dllocal_group[kq] and dllocal_group[kq].long then 
								dllocal_info_inst:SetText("Instance: |cffffd100" .. dllocal_group[kq].long .. "|r");
								dllocal_info_inst.frame:Show()
							else 
								dllocal_info_inst:SetText("") 
								dllocal_info_inst.frame:Hide()
							end
						end
					end)
				
					title:SetCallback("OnLeave", function()
						GameTooltip:Hide()
					end)
				
					quest:AddChild(title)

					local repText = ""
					local tooltip = ""

					if q.Honor > 0 then 
						repText = q.Honor .. " |TInterface\\AddOns\\Dailies\\Images\\pvp-arenapoints-icon:16|t" 
						tooltip = "|TInterface\\AddOns\\Dailies\\Images\\pvp-arenapoints-icon:16|t |cffa0a0a0+" .. q.Honor .. " Honor Points|r"
					end

					totalHonor = totalHonor + q.Honor
					
					if dllocal_reps[kq] then 
						for kr, r in Dailies.spairs(dllocal_reps[kq], function(t,a,b)
							return a < b
						end) do --sorted reps


                                                        if dllocal_repfaction[kr] == nil or dllocal_repfaction[kr] == dllocal_faction then 
                                                                repText = " |T" .. dllocal_repicons[kr].icon .. ":16|t" .. repText
                                                                local name, _, _, _, _, earnedValue = GetFactionInfoByID(kr)
                                                                tooltip = "|T" .. dllocal_repicons[kr].icon .. ":16|t |cffa0a0a0+" .. r .. " " .. (name or "Unknown Reputation") .. " rep|r\n" .. tooltip
                                                                
                                                                if totalReps[kr] == nil then
                                                                        totalReps[kr] = r
                                                                else
                                                                        totalReps[kr] = totalReps[kr] + r
                                                                end
							end
						end
					end
				
					local rep = AceGUI:Create("InteractiveLabel")
					rep:SetText(repText)
					rep:SetWidth(60)
					rep:SetJustifyH("RIGHT")
					rep:SetFont(GameFontNormal:GetFont(), 12)
				
					if tooltip ~= "" then 
						rep:SetCallback("OnEnter", function() 
							GameTooltip:SetOwner(rep.frame,"ANCHOR_NONE")
							GameTooltip:SetPoint("TOPLEFT", rep.frame,"TOPRIGHT", 10, 3)
							GameTooltip:SetText(tooltip)
						end) 
						
						rep:SetCallback("OnLeave", function()
							GameTooltip:Hide()
						end)
					end
				
					quest:AddChild(rep)

					local rewardText = ""

					if q.Money > 0 then
						rewardText = GetMoneyString(q.Money, true)
					end
					
					totalGold = totalGold + q.Money
					local reward = AceGUI:Create("InteractiveLabel")
					reward:SetText(rewardText)
					reward:SetWidth(80)
					reward:SetJustifyH("RIGHT")
					reward:SetFont(GameFontNormal:GetFont(), 12)
					quest:AddChild(reward)

					-- don't show arrows on All tab (quests are sorted by group)
					if dllocal_tabkey ~= "all" then 
						local moveup = AceGUI:Create("InteractiveLabel")
						moveup:SetWidth(20)
						moveup:SetJustifyH("CENTER")
						moveup:SetCallback("OnEnter", function() 
							GameTooltip:SetOwner(moveup.frame,"ANCHOR_NONE")
							GameTooltip:SetPoint("TOPLEFT", moveup.frame,"BOTTOMLEFT", 10, 0)
							GameTooltip:SetText("Move this daily up")
						end) 
					
						moveup:SetCallback("OnLeave", function()
							GameTooltip:Hide() 
						end)
					
						if count == 1 then 
							moveup:SetDisabled(true)
							moveup:SetText("|TInterface\\AddOns\\Dailies\\Images\\moveup:16|t")
						else
							moveup:SetText("|TInterface\\AddOns\\Dailies\\Images\\moveup:16|t")
							moveup:SetCallback("OnClick", function() 							
								local prev = 0

								for ko, o in pairs(dllocal_orderlist) do 
									if o == kq then
										prev = dllocal_orderlist[ko-1] 
									end
								end
 
								if prev ~= nil and prev ~= 0 then -- checking if top of list
									local ord = Dailies_Data.Toons[dllocal_charKey].Quests[prev].Order
									Dailies_Data.Toons[dllocal_charKey].Quests[prev].Order = Dailies_Data.Toons[dllocal_charKey].Quests[kq].Order
									Dailies_Data.Toons[dllocal_charKey].Quests[kq].Order = ord
									Dailies.ShowTabContent()
								end
							end)
						end
				
						quest:AddChild(moveup)
 
						local movedn = AceGUI:Create("InteractiveLabel")
						movedn:SetWidth(20)
						movedn:SetJustifyH("CENTER")
						
						movedn:SetCallback("OnEnter", function() 
							GameTooltip:SetOwner(movedn.frame,"ANCHOR_NONE")
							GameTooltip:SetPoint("TOPLEFT", movedn.frame,"BOTTOMLEFT", 10, 0)
							GameTooltip:SetText("Move this daily down")
						end)
				
						movedn:SetCallback("OnLeave", function()
							GameTooltip:Hide()
						end)
				
						movedn:SetText("|TInterface\\AddOns\\Dailies\\Images\\movedn:16|t")
						movedn:SetCallback("OnClick", function() 
							local prev = 0
							
							for ko, o in pairs(dllocal_orderlist) do 
								if o == kq then
									prev = dllocal_orderlist[ko+1]
								end
							end
 
							if prev ~= nil and prev ~= 0 then -- checking if bottom of list

							local ord = Dailies_Data.Toons[dllocal_charKey].Quests[prev].Order
							Dailies_Data.Toons[dllocal_charKey].Quests[prev].Order = Dailies_Data.Toons[dllocal_charKey].Quests[kq].Order
							Dailies_Data.Toons[dllocal_charKey].Quests[kq].Order = ord
							Dailies.ShowTabContent()
							end
						end)

						quest:AddChild(movedn)
					end

					local ignore = AceGUI:Create("InteractiveLabel")
					ignore:SetJustifyH("CENTER")
					
					if Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored == false then 
						ignore:SetText("|TInterface\\AddOns\\Dailies\\Images\\ignored:16|t")
						ignore:SetWidth(20)

						ignore:SetCallback("OnClick", function() 
							Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored = true
							Dailies.ShowTabContent()
						end)
						
						ignore:SetCallback("OnEnter", function() 
							GameTooltip:SetOwner(ignore.frame,"ANCHOR_NONE")
							GameTooltip:SetPoint("TOPLEFT", ignore.frame,"BOTTOMLEFT", 10, 0)
							GameTooltip:SetText("Move this daily to the Ignore list")
						end)
					else 
						ignore:SetText("|TInterface\\AddOns\\Dailies\\Images\\completed:16|t")
						ignore:SetWidth(20)
						
						ignore:SetCallback("OnClick", function() 
							Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored = false
							Dailies.ShowTabContent()
						end)
						
						ignore:SetCallback("OnEnter", function() 
							GameTooltip:SetOwner(ignore.frame,"ANCHOR_NONE")
							GameTooltip:SetPoint("TOPLEFT", ignore.frame,"BOTTOMLEFT", 10, 0)
							GameTooltip:SetText("Remove this daily from the Ignore list")
						end)
					end 

					ignore:SetCallback("OnLeave", function()
						GameTooltip:Hide()
					end)	
					
					quest:AddChild(ignore)

					--give alternative to group quest if any available (today's daily of the same group)
					local actualDaily = nil
					
					if dllocal_group[kq] then -- part of a group
						for kq2, q2 in pairs(dllocal_group) do 
							if dllocal_group[kq2].group == dllocal_group[kq].group and kq2 ~= kq then -- others from same group
								if Dailies_Data.Quests[kq2] and Dailies_Data.Quests[kq2].TodayUntil and Dailies_Data.Quests[kq2].TodayUntil > (time(date("!*t")) + dllocal_tzdiff) then 
									actualDaily = kq2
								end								
							end
						end
					end

					if actualDaily and dllocal_tabkey == "todo" then 
						local daily = AceGUI:Create("Label")
						daily:SetText(" |TInterface\\AddOns\\Dailies\\Images\\alternative:16|t|cff808080If you prefer, today's daily is actually |r|cffffd100" .. Dailies_Data.Quests[actualDaily].Title .. "|r")
						daily:SetFullWidth(true)
						daily:SetJustifyH("LEFT")
						daily:SetFont(GameFontNormal:GetFont(), 12)
						quest:AddChild(daily)
					end

					scroll:AddChild(quest)

					-- ensuring groups are only listed once
					if completed and dllocal_group[kq] then
						completedGroups[dllocal_group[kq].group] = true
					end

					previousHeader = header
				end
			end
		end

		-- adding generic groups when today's dailies are not known yet
		-- but only for the todo tab and only if no rep filter
		local extras = 0 -- how many to add to the tab count
 
		if Dailies_Data.Toons[dllocal_charKey].RepFilter == nil then 
			-- find all groups with no quest listed
			for km, m in pairs(dllocal_group) do 
				if m.faction == nil or m.faction == dllocal_faction then 
					for kall, all in pairs(dllocal_questTabs.ToDo) do 
						if km == kall then 
							listedGroups[m.group] = true
						end
					end
					
					for kall, all in pairs(dllocal_questTabs.Ignored) do 
						if km == kall then 
							listedGroups[m.group] = true
						end
					end
				
					for kall, all in pairs(dllocal_questTabs.Completed) do 
						if km == kall then 
							listedGroups[m.group] = true
						end
					end
				end
			end

			for km, m in pairs(dllocal_group) do 
				local skipgeneric = false

				--check group is for the right expac
				if m.expac == nil or (Dailies_Settings.showClassicDailies and m.expac == 1) or (Dailies_Settings.showTBCDailies and m.expac == 2) or
					(Dailies_Settings.showWotLKDailies and m.expac == 3) or (Dailies_Settings.showCataDailies and m.expac == 4) then

					if dllocal_seasonal[kq] == nil or (Dailies_Settings.showSeasonalDailies and dllocal_seasonal[kq] ~= nil) then 
						if m.faction == nil or m.faction == dllocal_faction then 
							if Dailies_Settings.showOnlyForKnownProfessions and dllocal_prof[km] and Dailies_Data.Toons[dllocal_charKey].Professions[dllocal_prof[km]] == nil then 
								skipgeneric = true
							end
 
							if skipgeneric == false then 
								local found = false
								
								for kl, l in pairs(listedGroups) do 
									if m.group == kl then 
										found = true 
									end
								end
 
								if found == false then
									extras = extras + 1
									listedGroups[m.group] = true 

									if dllocal_tabkey == "todo" then 
										local quest = AceGUI:Create("SimpleGroup")
										quest:SetFullWidth(true)
										quest:SetAutoAdjustHeight(true)
										quest:SetLayout("Flow")

										local title = AceGUI:Create("InteractiveLabel")
										title:SetText("|TInterface\\AddOns\\Dailies\\Images\\available:16|t |cff808080Unknown " .. m.group .. " Daily|r")
										title:SetWidth(360)
										title:SetJustifyH("LEFT")
										title:SetFont(GameFontNormal:GetFont(), 12)

										title:SetCallback("OnClick", function() 
											if Dailies_Settings.showQuestInfoPanel then 
												local groupCount = 0
												
												for km2, m2 in pairs(dllocal_group) do 
													if m.group == m2.group then 
														groupCount = groupCount + 1
													end
												end
 
												dllocal_info_heading:SetText("") 
												dllocal_info_npc:SetText(" ") 
												dllocal_info_zone:SetText(" ")
												dllocal_info_count:SetText(" ")
												dllocal_info_coords:SetText(" ")
												dllocal_info_inst:SetText(" ")
												dllocal_info_inst.frame:Hide()
												dllocal_info_desc:SetText("This daily quest is taken randomly from a pool of |cffffd100" .. groupCount .. " quests|r.|nWe don't yet know which one is the selected one for today.");  
											end
										end) 
										
										quest:AddChild(title)
										scroll:AddChild(quest)
									end
								end
							end
						end
					end
				end
			end
		end
		
		dllocal_tabgroup:SetTabs({
			{value="todo", text="To Do ("..(Dailies.count(dllocal_questTabs.ToDo) + extras)..")"},
			{value="completed", text="Completed ("..Dailies.count(dllocal_questTabs.Completed)..")"},
			{value="ignored", text="Ignored ("..Dailies.count(dllocal_questTabs.Ignored)..")"},
			{value="all", text="All Dailies ("..(Dailies.count(dllocal_questTabs.All))..")"},
			{value="stats", text="Statistics"}})

			-- if absolutely nothing was found, put a default message
			if Dailies.count(list) == 0 then 
				local msg = AceGUI:Create("Label")
				msg:SetText("\n\nYou do not appear to have any matching daily quest")
				msg:SetFullWidth(true)
				msg:SetJustifyH("CENTER")
				msg:SetFont(GameFontNormal:GetFont(), 12)
				scroll:AddChild(msg)
			end

			if showTotal then 
				local total = AceGUI:Create("SimpleGroup")
				total:SetFullWidth(true)
				total:SetLayout("Flow")

				local heading = AceGUI:Create("Heading")
				heading:SetText("")
				heading:SetFullWidth(true)
				heading.left:SetAlpha(0.4)
				heading.right:SetAlpha(0.4)
				total:AddChild(heading)

				local totaltext = AceGUI:Create("Label")
				totaltext:SetText("|cffc0c0c0Total for all listed Dailies:|r")
				totaltext:SetWidth(300)
				totaltext:SetJustifyH("LEFT")
				totaltext:SetFont(GameFontNormal:GetFont(), 12)
				total:AddChild(totaltext)
 
				local repText = ""
				local tooltip = ""

				if totalHonor > 0 then 
					repText = " |TInterface\\AddOns\\Dailies\\Images\\pvp-arenapoints-icon:16|t" 
					tooltip = "|TInterface\\AddOns\\Dailies\\Images\\pvp-arenapoints-icon:16|t |cffa0a0a0+" .. totalHonor .. " Honor Points|r\n"
				end

				for kr, r in pairs(totalReps) do 
					if dllocal_repfaction[kr] == nil or dllocal_repfaction[kr] == dllocal_faction then 
						repText = " |T" .. dllocal_repicons[kr].icon .. ":16|t" .. repText
						local name, _, _, _, _, earnedValue = GetFactionInfoByID(kr)
						tooltip = "|T" .. dllocal_repicons[kr].icon .. ":16|t |cffa0a0a0+" .. r .. " " .. (name or "Unknown Reputation") .. " rep|r\n" .. tooltip
					end
				end
				
				local totalrep = AceGUI:Create("InteractiveLabel")
				totalrep:SetText(repText)
				totalrep:SetWidth(230)
				totalrep:SetJustifyH("RIGHT")
				totalrep:SetFont(GameFontNormal:GetFont(), 12)
				
				if tooltip ~= "" then 
					totalrep:SetCallback("OnEnter", function() 
						GameTooltip:SetOwner(totalrep.frame,"ANCHOR_NONE")
						GameTooltip:SetPoint("TOPLEFT", totalrep.frame,"TOPRIGHT", 10, 3)
						GameTooltip:SetText(tooltip)
					end) 
				
					totalrep:SetCallback("OnLeave", function() GameTooltip:Hide() end)
				end
				
				total:AddChild(totalrep)

				local goldString = ""
				
				if totalGold > 0 then
					goldString = GetMoneyString(totalGold, true)
				end
				
				totalvalue = AceGUI:Create("Label")
				totalvalue:SetText(goldString)
				totalvalue:SetWidth(80)
				totalvalue:SetJustifyH("RIGHT")
				totalvalue:SetFont(GameFontNormal:GetFont(), 12)
				total:AddChild(totalvalue)

				totalspacer = AceGUI:Create("Label")
				totalspacer:SetText("")
				totalspacer:SetWidth(3*20)
				totalspacer:SetFont(GameFontNormal:GetFont(), 12)
				total:AddChild(totalspacer)

				dllocal_tabgroup:AddChild(total)
			end

			if Dailies_Settings.showQuestInfoPanel then 
				local info = AceGUI:Create("SimpleGroup")
				info:SetFullWidth(true)
				info:SetLayout("Flow")

				dllocal_info_heading = AceGUI:Create("Heading")
				dllocal_info_heading:SetText("")
				dllocal_info_heading:SetFullWidth(true)
				info:AddChild(dllocal_info_heading)
 
				dllocal_info_npc = AceGUI:Create("Label")
				dllocal_info_npc:SetText(" ")
				dllocal_info_npc:SetRelativeWidth(0.50)
				dllocal_info_npc:SetJustifyH("LEFT")
				dllocal_info_npc:SetFont(GameFontNormal:GetFont(), 12)
				info:AddChild(dllocal_info_npc)
 
				dllocal_info_zone = AceGUI:Create("Label")
				dllocal_info_zone:SetText(" ")
				dllocal_info_zone:SetRelativeWidth(0.50)
				dllocal_info_zone:SetJustifyH("RIGHT")
				dllocal_info_zone:SetFont(GameFontNormal:GetFont(), 12)
				info:AddChild(dllocal_info_zone)
 
				dllocal_info_count = AceGUI:Create("Label")
				dllocal_info_count:SetText(" ")
				dllocal_info_count:SetRelativeWidth(0.50)
				dllocal_info_count:SetJustifyH("LEFT")
				dllocal_info_count:SetFont(GameFontNormal:GetFont(), 12)
				info:AddChild(dllocal_info_count)
 
				dllocal_info_coords = AceGUI:Create("Label")
				dllocal_info_coords:SetText(" ")
				dllocal_info_coords:SetRelativeWidth(0.50)
				dllocal_info_coords:SetJustifyH("RIGHT")
				dllocal_info_coords:SetFont(GameFontNormal:GetFont(), 12)
				info:AddChild(dllocal_info_coords) 
 
				dllocal_info_inst = AceGUI:Create("Label")
				dllocal_info_inst:SetText(" ")
				dllocal_info_inst:SetRelativeWidth(0.50)
				dllocal_info_inst:SetJustifyH("LEFT")
				dllocal_info_inst:SetFont(GameFontNormal:GetFont(), 12)
				info:AddChild(dllocal_info_inst)
 
				dllocal_info_desc = AceGUI:Create("Label")
				dllocal_info_desc:SetText("Hover over one of the quests in the list to see more details\n \n ")
				dllocal_info_desc:SetFullWidth(true)
				dllocal_info_desc:SetJustifyH("CENTER")
				dllocal_info_desc:SetFont(GameFontNormal:GetFont(), 11)
				info:AddChild(dllocal_info_desc)

				dllocal_tabgroup:AddChild(info)
			end
		end
	end
end

function Dailies.ClassifyQuests()
	dllocal_questTabs = {}
	dllocal_questTabs.ToDo = {}
	dllocal_questTabs.Completed = {}
	dllocal_questTabs.Ignored = {}
	dllocal_questTabs.All = {}

	local completedGroups = {} -- used to not repeat completed quests from the same group
	local listedGroups = {} -- used to not repeat completed quests from the same group
	local listedExclu = {} -- used to not repeat completed quests from the same group
	local first = true -- used to show the first quest in broker
	
	for kq, q in Dailies.spairs(Dailies_Data.Quests, function(t,a,b)
		return Dailies_Data.Toons[dllocal_charKey].Quests[a].Order < Dailies_Data.Toons[dllocal_charKey].Quests[b].Order
	end) do --all dailies
		-- super dirty way to handle quest expac
		local expac = dllocal_expac[q.Zone]

		if expac == nil or 
                   (Dailies_Settings.showTBCDailies and expac == 2) or
		   (Dailies_Settings.showWotLKDailies and expac == 3) or 
                   (Dailies_Settings.showCataDailies and expac == 4) then

			if dllocal_seasonal[kq] == nil or (Dailies_Settings.showSeasonalDailies and dllocal_seasonal[kq] ~= nil) then 
				-- only show quests available to this faction
				if Dailies_Data.Quests[kq].Factions and Dailies_Data.Quests[kq].Factions[dllocal_faction] == 1 then 
					if Dailies_Data.Quests[kq].Seen and Dailies_Data.Quests[kq].Seen[GetRealmName()] == 1 then 
						if dllocal_group[kq] == nil or dllocal_group[kq].faction == nil or dllocal_group[kq].faction == dllocal_faction then 
							local skip = false

							local completed	= C_QuestLog.IsQuestFlaggedCompleted(kq)
							--	if completed and Dailies_Data.Quests[kq].TodayUntil == nil then completed = false end 

							-- Check if we already have the quest in our log
							local alreadyHaveIt = Dailies.AlreadyHaveQuest(kq)

							local todaysDaily = true
							local haveAnotherAlready = false

							-- check if that quest if part of a group where you can only have 1 of the group at the time
							-- for example the fishing daily, or the cooking daily, or the daily dungeon
							if dllocal_group[kq] then -- part of a group
								-- if a group, check if it's todays
								if q.TodayUntil == nil then 
									todaysDaily = false
								elseif (time(date("!*t")) + dllocal_tzdiff) > q.TodayUntil then
									q.TodayUntil = nil
									todaysDaily = false 
								end

								for kq2, q2 in pairs(dllocal_group) do 
									if dllocal_group[kq2].group == dllocal_group[kq].group and kq2 ~= kq then
										if Dailies.AlreadyHaveQuest(kq2) then
											haveAnotherAlready = true
										end
									end
								end
							end

							-- This is to make sure the completed quest has actually been completed, and is not just showing because it's part of a completed group
							if completed == true and todaysDaily == false then
								completed = false
							end

							-- add to listed groups to avoid the generic group line
							if completed and dllocal_group[kq] then
								listedGroups[dllocal_group[kq].group] = true
							end

							if completed and dllocal_exclu[kq] then
								listedGroups[dllocal_exclu[kq].group] = true
							end
 
							if Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored and dllocal_group[kq] then
								listedGroups[dllocal_group[kq].group] = true
							end
				
							if Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored and dllocal_exclu[kq] then
								listedGroups[dllocal_exclu[kq].group] = true
							end

							if alreadyHaveIt == false and todaysDaily == false then
								skip = true
							end
				
							if haveAnotherAlready == true and todaysDaily == true then
								skip = true
							end

							if completed then
								skip = false
							end

							-- check if that quest is a temporaty quest, to be replaced by another at some point
							-- if the new one exists, then never show the old one
							-- for example the SSO phase quests
							if dllocal_temp[kq] then -- part of a temp
								if Dailies_Data.Quests[dllocal_temp[kq]] then 
									if Dailies_Data.Quests[dllocal_temp[kq]].Seen and Dailies_Data.Quests[dllocal_temp[kq]].Seen[GetRealmName()] then 
										skip = true 
									end
								end
							end 

							if dllocal_group[kq] and completedGroups[dllocal_group[kq].group] then
								skip = true
							end
				
							if dllocal_exclu[kq] and completedGroups[dllocal_exclu[kq].group] then
								skip = true
							end
							
							if dllocal_require[kq] and not C_QuestLog.IsOnQuest(dllocal_require[kq]) then
								skip = true
							end

							-- professions
							if Dailies_Settings.showOnlyForKnownProfessions and dllocal_prof[kq] and Dailies_Data.Toons[dllocal_charKey].Professions[dllocal_prof[kq]] == nil
								then skip = true
							end

							-- add to listed groups to avoid the generic group line
							if dllocal_group[kq] and listedGroups[dllocal_group[kq].group] == nil then
								listedGroups[dllocal_group[kq].group] = true
							end
 
							-- check quests against filter
							if Dailies_Data.Toons[dllocal_charKey].RepFilter ~= nil then 
								if dllocal_reps[kq] then 
									for kr, r in Dailies.spairs(dllocal_reps[kq], function(t,a,b)
										return a < b
									end) do --sorted reps
										if kr ~= Dailies_Data.Toons[dllocal_charKey].RepFilter then
											skip = true
										end
									end
								else 
									skip = true -- no rep attached, skip if filter is active
								end
							end
 
							-- put in buckets
							dllocal_questTabs.All[kq] = 1
	
							if skip == false and completed == true then
								dllocal_questTabs.Completed[kq] = 1
							elseif skip == false and Dailies_Data.Toons[dllocal_charKey].Quests[kq].Ignored then
								dllocal_questTabs.Ignored[kq] = 1
							elseif skip == false then
								dllocal_questTabs.ToDo[kq] = 1 
					
								if first then 
									first = false
									dllocal_brokerlabel = Dailies_Data.Quests[kq].Title
						
									if alreadyHaveIt then 
										if Dailies.ReadyToComplete(kq) then 
											dllocal_brokervalue = "|cff00ff00Turn In|r"
										else							
											dllocal_brokervalue = ""
										end
									else	
										dllocal_brokervalue = "|cff4040ffPick Up|r"
									end
	
									if Dailies_Broker then
										Dailies_Broker.text = dllocal_brokervalue .. " " .. dllocal_brokerlabel
									end
								end
							end
 
							-- ensuring groups are only listed once
							if completed and dllocal_group[kq] then
								completedGroups[dllocal_group[kq].group] = true
							end
			
							if completed and dllocal_exclu[kq] then
								completedGroups[dllocal_exclu[kq].group] = true 
							end
						end
					end
				end
			end
		end
	end

	if Dailies.count(dllocal_questTabs.ToDo) == 0 then 
		dllocal_brokervalue = "" 
		dllocal_brokerlabel = "All Done!"
		
		if Dailies_Broker then
			Dailies_Broker.text = dllocal_brokervalue .. " " .. dllocal_brokerlabel	
		end
	end
end

function Dailies.MakeGroupDaily(qid)
	-- if part of a group, mark as today's daily
	if dllocal_group[qid] then -- part of a group
		if Dailies_Data.Quests[qid] then 
			--Dailies_Data.Quests[qid].Today = true 
			local reset = Dailies.DailyResetTime()
	
			if Dailies_Data.Quests[qid].TodayUntil == nil or reset > Dailies_Data.Quests[qid].TodayUntil then
				Dailies_Data.Quests[qid].TodayUntil = reset
			end
		end

		for kq, q in pairs(dllocal_group) do 
			if dllocal_group[kq].group == dllocal_group[qid].group and kq ~= qid then -- others from same group
				if Dailies_Data.Quests[kq] then 
					--Dailies_Data.Quests[kq].Today = nil 
					Dailies_Data.Quests[kq].TodayUntil = nil
				end
			end
		end
	end
end

function Dailies.AlreadyHaveQuest(qid)
	for i=1, GetNumQuestLogEntries() do 
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
			frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
			isTask, isStory = GetQuestLogTitle(i);

		if qid == questID then return
			true
		end
	end

	return false
end

function Dailies.ReadyToComplete(qid)
	for i=1, GetNumQuestLogEntries() do 
		local title, level, suggestedGroup, isHeader, isCollapsed, isComplete,
			frequency, questID, startEvent, displayQuestID, isOnMap, hasLocalPOI,
			isTask, isStory = GetQuestLogTitle(i);

		if qid == questID then
			return isComplete
		end	
	end

	return false
end

function Dailies.sendProgress(id, bytesSent, bytesTotal)
	local percentComplete = bytesSent/bytesTotal * 100
	local recipient, part = id:match("([^:]+):(%d+)")

	if Dailies._recipientQueue and Dailies._recipientQueue[recipient] then
		local totalParts = Dailies._recipientQueue[recipient][1]
		
		if part and tonumber(part) == totalParts and percentComplete == 100 then
			Dailies._recipientQueue[recipient] = nil
		end
	end
	
	C_Timer.After(1, function()
		if not Dailies._recipientQueue or Dailies.count(Dailies._recipientQueue) == 0 then
			Dailies:RemoveFilter()
		end
	end)
end

function Dailies:OnCommReceived(prefix, message, distribution, sender)
	if prefix == dllocal_prefix and sender ~= UnitName("player") then
		--Someone requested the list of today's dailies
		if message == "GET_TODAYS_DAILIES" or message == "GET_ALL_DAILIES" then
			Dailies._recipientQueue = Dailies._recipientQueue or {}
			Dailies._recipientQueue[sender] = nil
			
			local count, totalLen = 0, 0
			
			for kq, q in pairs(Dailies_Data.Quests) do 
				if q.Factions[dllocal_faction] == 1 then
					if (message == "GET_ALL_DAILIES") or (message == "GET_TODAYS_DAILIES" and (dllocal_group[kq] and q.TodayUntil and q.TodayUntil > (time(date("!*t")) + dllocal_tzdiff))) then -- today's daily or all dailies						
						--send each daily back						
						local ser = kq.."|"..Dailies.serialize(q):gsub(" = ", "="):gsub(" ", ""):gsub(" }", "}")
						totalLen = totalLen + #ser
 
						if Dailies.CheckExists(sender) then
							Dailies:AddFilter()
							count = count + 1
							
							local messageKey = format("%s:%d",sender,count)
							Dailies:SendCommMessage(dllocal_prefix, ser, "WHISPER", sender, "NORMAL", Dailies.sendProgress, messageKey)
						end
					end
				end
			end
			
			if count > 0 then -- we queued at least 1 message
				Dailies._recipientQueue[sender] = {count, totalLen, GetTime()}
			end
		else
			if message ~= nil then 
				if string.find(message, "|") then 	
					local amess = Dailies.split(message, "|")
					local id = tonumber(amess[1])
					local data = amess[2]

					if dllocal_timer_handle then
						dllocal_timer_handle:Cancel()
					end
	
					local newDaily = Dailies.deserialize(data)

					if newDaily.Title and newDaily.Zone and newDaily.Text then 
						-- check the data received is actually populated.
						-- Zone is typically one of the last things to be updated
						Dailies_Data.Quests[id] = Dailies_Data.Quests[id] or {
							Title = newDaily.Title or "";
							Text = newDaily.Text or "";
							Frequency = newDaily.Frequency or "";
							Money = newDaily.Money or 0;
							Xp = newDaily.Xp or 0;
							Honor = newDaily.Honor or 0;
							SubZone = newDaily.SubZone or "";
							Zone = newDaily.Zone or "";
							NPC = newDaily.NPC or "";
						}

						-- don't overwrite Faction. Add to it instead
						Dailies_Data.Quests[id].Factions = Dailies_Data.Quests[id].Factions or {}
						Dailies_Data.Quests[id].Factions[dllocal_faction] = 1

						if newDaily.TodayUntil ~= nil then 
							if Dailies_Data.Quests[id].TodayUntil == nil or Dailies_Data.Quests[id].TodayUntil < newDaily.TodayUntil then 
								Dailies_Data.Quests[id].TodayUntil = newDaily.TodayUntil
								
								if dllocal_group[id] and Dailies_Settings.showReceivedDailies then
									print("|cffff00ff[Dailies]|r Today's "..dllocal_group[id].group.. " daily is |cffffd100" .. newDaily.Title .. "|r (from |cffffd100" .. GetPlayerLink(sender, sender) .. "|r)")
								end
							end

							--mark as today's daily if it's a grouped one
							Dailies.MakeGroupDaily(id)
						end

						Dailies_Data.Quests[id].Seen = Dailies_Data.Quests[id].Seen or {}
						Dailies_Data.Quests[id].Seen[GetRealmName()] = 1

						Dailies_Data.Toons[dllocal_charKey].Quests[id] = Dailies_Data.Toons[dllocal_charKey].Quests[id] or {
							Ignored = false;
							Order = Dailies.count(Dailies_Data.Toons[dllocal_charKey].Quests)+1;
						}

						Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration = Dailies_Data.Toons[dllocal_charKey].Quests[id].Duration or {
							Current = nil;	
							Last = nil;	
							Fastest = nil;	
							Slowest = nil;	
						}
 
						dllocal_timer_handle = C_Timer.NewTimer(5, function()
							if dllocal_frame and dllocal_frame:IsVisible() then 
								Dailies.ShowTabContent()
							end
						end, 1)
					end
				end
			end
		end
	elseif prefix == dllocal_prefix_version and sender ~= UnitName("player") then 
		if message == 'VERSION' then 
			if Dailies.CheckExists(sender) then
				Dailies:SendCommMessage(dllocal_prefix_version, dllocal_version, "WHISPER", sender )
			end
		else
			print("|cffff00ff[Dailies]|r |cffffd100" .. GetPlayerLink(sender, sender) .. "|r is using |cffffd100v" .. message .. "|r") 
		end
	end
end 

function Dailies.CheckExists(player)
	-- don't send update request when guild frame is open, it's already requesting / breaks show offline behavior
	if not GuildFrame:IsShown() then
		-- this is not instant we need to update our cache of online guildies at the respective event
		-- the server response to request for new guild information is also throttled to ~10sec so data will never be 100% correct/real-time
		C_GuildInfo.GuildRoster()
	end
	
	local fullName = player:match("([^%-]+%-.+)")
		
	if not fullName then
		fullName = format("%s-%s",player,GetNormalizedRealmName())
	end

	if fullName then -- check our last known good information
		return Dailies._guildOnlineCache and Dailies._guildOnlineCache[fullName]
	end
end

function Dailies_SlashCommandHandler( msg )
	if msg == 'version' then 
		print("|cffff00ff[Dailies]|r Sending version check.")
 
		if dllocal_inGuild then 
			Dailies:SendCommMessage(dllocal_prefix_version, "VERSION", "GUILD", "") 
		end
	else 
		dllocal_frame = Dailies.getFrame()
	end
end

SlashCmdList["Dailies"] = Dailies_SlashCommandHandler
SLASH_Dailies1 = "/Dailies"

_G[dllocal_addonName] = Dailies -- comment this out if we don't want our addon object accessible from the outside
