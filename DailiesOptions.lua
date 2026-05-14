local AceConfig = LibStub("AceConfig-3.0")

local dllocal_minimapicon = LibStub("LibDBIcon-1.0")

local dllocal_options = {
	name = "Dailies",
	handler = Dailies,
	type = "group",
	args = {
		header10 = {
			type = "header",
			name = "General",
			order = 10,
		},
		showMinimapButton = {
			type = "toggle",
			name = "Show the Minimap button",
			desc = "Display a Minimap button to quickly access the addon interface or options.",
			get = function(info)
				return not Dailies_Settings.minimapButtonPosition.hide
			end,
			set = function(info, val)
				if val then
					dllocal_minimapicon:Show("Dailies_Broker")
				else
					dllocal_minimapicon:Hide("Dailies_Broker")
				end
				Dailies_Settings.minimapButtonPosition.hide = not val
				Dailies_Settings.showMinimapButton = val
			end,
			width = "full",
			order = 20,
		}, 
		header20 = {
			type = "header",
			name = "Scans",
			order = 30,
		},
			runScanOnLogin = {
			type = "toggle",
			name = "Perform an automatic scan on login",
			desc = "This runs a scan to find out about today's dailies when you enter the game.",
			get = function(info)
				return Dailies_Settings.runScanOnLogin
			end,
			set = function(info, val)
				Dailies_Settings.runScanOnLogin = val
			end,
			width = "full",
			order = 40,
		},
		scanForAnyDailies = {
			type = "toggle",
			name = "Scan for all daily quests, not just today's dailies",
			desc = "Check this to make the scan look for *any* daily quest, not just the dailies specific to today.",
			get = function(info)
				return Dailies_Settings.scanForAnyDailies
			end,
			set = function(info, val)
				Dailies_Settings.scanForAnyDailies = val
			end,
			width = "full",
			order = 50,
		},
		header30 = {
			type = "header",
			name = "Options",
			order = 60,
		},
		showReceivedDailies = {
			type = "toggle",
			name = "Show incoming messages about today's dailies",
			desc = "This lets you know via a chat message when you receive the information about today's dailies from another player.",
			get = function(info)
				return Dailies_Settings.showReceivedDailies
			end,
			set = function(info, val)
				Dailies_Settings.showReceivedDailies = val
			end,
			width = "full",
			order = 70,
		},
		showQuestRewardTotal = {
			type = "toggle",
			name = "Display the total gold and reputation to be earned",
			desc = "This adds a summary line at the bottom of the daily list with the gold and repuration totals.",
			get = function(info)
				return Dailies_Settings.showQuestRewardTotal
			end,
			set = function(info, val) 
				Dailies_Settings.showQuestRewardTotal = val
				if dllocal_frame and dllocal_frame:IsVisible() then
					Dailies.ShowTabContent()
				end
			end,	
			width = "full",
			order = 80,
		},
		showQuestInfoPanel = {
			type = "toggle",
			name = "Display the quest information panel",
			desc = "This opens up a little panel below the quest list and provides the quest description, quest giver name and area.",
			get = function(info) return Dailies_Settings.showQuestInfoPanel end,
			set = function(info, val) 
				Dailies_Settings.showQuestInfoPanel = val
				if dllocal_frame and dllocal_frame:IsVisible() then
					Dailies.ShowTabContent()
				end
			end,
			width = "full",
			order = 90,
		},
		showOnlyForKnownProfessions = {
			type = "toggle",
			name = "Only show profession quests for known professions",
			desc = "This will hide quests related to professions this toon doesn't have.",
			get = function(info)
				return Dailies_Settings.showOnlyForKnownProfessions
			end,
			set = function(info, val) 
				Dailies_Settings.showOnlyForKnownProfessions = val
				if dllocal_frame and dllocal_frame:IsVisible() then
					Dailies.ShowTabContent()
				end
			end,
			width = "full",
			order = 95,
		},
		header40 = {
			type = "header",
			name = "Automation",
		},
		autoAcceptQuests = {
			type = "toggle",
			name = "Auto-accept quests in your to-do list",
			desc = "This will automatically accept any quest from your To-Do list whenever you acces the quest giver.",
			get = function(info)
				return Dailies_Settings.autoAcceptQuests
			end,
			set = function(info, val)
				Dailies_Settings.autoAcceptQuests = val
			end,
			width = "full",
			order = 110,
		},
		autoCompleteQuests = {
			type = "toggle",
			name = "Auto-complete quests in your to-do list",
			desc = "This will automatically complete any quest from your To-Do list whenever you acces the quest giver - Assuming there is no reward to pick.",
			get = function(info)
				return Dailies_Settings.autoCompleteQuests
			end,
			set = function(info, val)
				Dailies_Settings.autoCompleteQuests = val
			end,
			width = "full",
			order = 120,
		},
		header50 = {
			type = "header",
			name = "Categories",
			order = 130,
		},
		showTBCDailies = {
			type = "toggle",
			name = "Show TBC Dailies",
			desc = "Show dailies linked to The Burning Crusade content.",
			get = function(info)
				return Dailies_Settings.showTBCDailies
			end,
			set = function(info, val) 
				Dailies_Settings.showTBCDailies = val 
				-- need async otherwise the quest is not detected as completed
				C_Timer.After(0.2, function()	
					Dailies.ClassifyQuests() 
					if dllocal_frame and dllocal_frame:IsVisible() then
						Dailies.ShowTabContent()
					end
				end) 
			end,
			width = "full",
			order = 141,
		},
		showWotLKDailies = {
			type = "toggle",
			name = "Show WotLK Dailies",
			desc = "Show dailies linked to Wrath of the Lich King content.",
			get = function(info)
				return Dailies_Settings.showWotLKDailies
			end,
			set = function(info, val)
				Dailies_Settings.showWotLKDailies = val 
				-- need async otherwise the quest is not detected as completed
				C_Timer.After(0.2, function()	
					Dailies.ClassifyQuests() 
					if dllocal_frame and dllocal_frame:IsVisible() then
						Dailies.ShowTabContent()
					end
				end) 
			end,
			width = "full",
			order = 142,
		},
		showCataDailies = {
			type = "toggle",
			name = "Show Cata Dailies",
			desc = "Show dailies linked to Cataclysm content.",
			get = function(info)
				return Dailies_Settings.showCataDailies
			end,
			set = function(info, val)
				Dailies_Settings.showCataDailies = val 
				-- need async otherwise the quest is not detected as completed
				C_Timer.After(0.2, function()	
					Dailies.ClassifyQuests() 
					if dllocal_frame and dllocal_frame:IsVisible() then
						Dailies.ShowTabContent()
					end
				end) 
			end,
			width = "full",
			order = 143,
		},
		showSeasonalDailies = {
			type = "toggle",
			name = "Show Seasonal Dailies",
			desc = "Show dailies linked to seasonal events (like Brewfest or Midsummer Fire Festival for example).",
			get = function(info)
				return Dailies_Settings.showSeasonalDailies
			end,
			set = function(info, val) 
				Dailies_Settings.showSeasonalDailies = val 
				-- need async otherwise the quest is not detected as completed
				C_Timer.After(0.2, function()	
					Dailies.ClassifyQuests() 
					if dllocal_frame and dllocal_frame:IsVisible() then
						Dailies.ShowTabContent()
					end
				end) 
			end,
			width = "full",
			order = 160,
		},
		header60 = {
			type = "header",
			name = "Contact",
			order = 170,
		},
		credits = {
			type = "description",
			name = " Join the discord server to bugs/suggestions/comments:\n |cffffd100https://discord.gg/MpfDeBZ|r\n\n Many thanks to |cffffd100Xerseus @ Pagle|r and |cffffd100Komanchi|r for their help getting the quest lists\n\nHope you like the addon,\n /Hug from Zuwo@Dreamscythe Horde aka Cixi/Gaya@Remulos Alliance\n\n",
			width = "full",
			fontSize = "medium",
			order = 180,
		},
	}
}

function Dailies:RegisterOptions()
	LibStub("AceConfig-3.0"):RegisterOptionsTable("Dailies", dllocal_options, nil)
end

function Dailies:RegisterMinimapButton()
	dllocal_minimapicon:Register("Dailies_Broker", Dailies_Broker, Dailies_Settings.minimapButtonPosition)
	
	if Dailies_Settings.minimapButtonPosition.hide then
		dllocal_minimapicon:Hide("Dailies_Broker"); dllocal_minimapicon:Hide("Dailies_Broker") 
	else 
		dllocal_minimapicon:Show("Dailies_Broker"); dllocal_minimapicon:Show("Dailies_Broker") 
	end
end
