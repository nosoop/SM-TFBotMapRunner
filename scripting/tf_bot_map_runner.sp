/**
 * This is an updated version of the old "[TF2] Bot-only Map Override" plugin.
 */
#pragma semicolon 1

#include <sourcemod>
#include <mapchooser>
#include <tf2>
#tryinclude <steamtools>

#pragma newdecls required

#define PLUGIN_VERSION "0.4.8"
public Plugin myinfo = {
	name = "[TF2] Bot Map Runner",
	author = "nosoop",
	description = "Forces the server to cycle through maps with bot support when the player count is too low. #botsrights",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFBotMapRunner"
}

#define MAP_NAME_LENGTH 96
#define OVERRIDE_MAPLIST "configs/bot_map_runner.txt"

ArrayList g_ValidBotMaps;

float g_flServerMapTriggerTime;

ConVar g_ConVarDurationFromMapStart, g_ConVarDurationFromDisconnect, g_ConVarPlayerCountThreshold;

public void OnPluginStart() {
	g_ValidBotMaps = new ArrayList(MAP_NAME_LENGTH);
	
	LoadTranslations("mapchooser.phrases");
	
	CreateConVar("botmaprunner_version", PLUGIN_VERSION, "Current version of Bot Map Runner.", FCVAR_NOTIFY | FCVAR_DONTRECORD);

	RegAdminCmd("sm_botmap", AdminCmd_BotMap, ADMFLAG_CHANGEMAP, "Immediately changes to a bot-compatible map.");
	RegAdminCmd("sm_setnextbotmap", AdminCmd_SetNextBotMap, ADMFLAG_CHANGEMAP, "Changes the next map to a bot-compatible map.");
	
	RegAdminCmd("sm_botmap_refresh", AdminCmd_RefreshMapList, ADMFLAG_CHANGEMAP, "Refreshes the bot map list.");
	
	HookEvent("teamplay_game_over", Hook_OnGameOver, EventHookMode_PostNoCopy);
	HookEvent("player_disconnect", Hook_OnPlayerDisconnect, EventHookMode_Post);
	
	HookEvent("player_spawn", Hook_OnPlayerSpawn, EventHookMode_Post);
	
	g_ConVarPlayerCountThreshold = CreateConVar("sm_botmap_playercount", "2",
			"Server is considered below the player count threshold if there are fewer than this number of players.  " ...
			"If set to 'quota', then the server uses tf_bot_quota or sm_bot_quota as the threshold.");
	
	g_ConVarDurationFromMapStart = CreateConVar("sm_botmap_duration_frommapstart", "90.0",
			"How long before a map change if the server is below the player count threshold on map start.",
			_, true, 0.0);
	
	g_ConVarDurationFromDisconnect = CreateConVar("sm_botmap_duration_fromdisconnect", "90.0",
			"How long before a map change when a player disconnect puts the player count below the threshold.",
			_, true, 0.0);
	
	AutoExecConfig();
	
	FindConVar("sm_nextmap").AddChangeHook(OnNextMapChanged);
}

public void OnMapStart() {
	g_flServerMapTriggerTime = 0.0;
}

public void OnConfigsExecuted() {
	GenerateBotMapLists();
	
	// We check here to make sure we're not stranded on a bot map and cvar data has been updated.
	if (IsLowPlayerCount() && !IsCurrentMapSuitable() && GetConnectingPlayerCount() == 0) {
		PrintToServer("No players detected.  Changing map in %d seconds...",
				RoundToFloor(g_ConVarDurationFromMapStart.FloatValue));
		CreateBotChangeMapTimer(g_ConVarDurationFromMapStart.FloatValue);
	}
}

public Action AdminCmd_BotMap(int client, int nArgs) {
	ShowActivity(client, "Changing to a random bot supported map...");
	CreateTimer(5.0, Timer_AdminCmdBotMap, _, TIMER_FLAG_NO_MAPCHANGE);
	return Plugin_Handled;
}

public Action AdminCmd_SetNextBotMap(int client, int nArgs) {
	char nextmap[MAP_NAME_LENGTH];
	if (OverrideNextMapForBot(nextmap, sizeof(nextmap))) {
		ShowActivity(client, "%t", "Changed Next Map", nextmap);
		LogAction(client, -1, "\"%L\" changed nextmap to \"%s\"", client, nextmap);
	}
	return Plugin_Handled;
}

public Action AdminCmd_RefreshMapList(int client, int nArgs) {
	GenerateBotMapLists();
	return Plugin_Handled;
}

public void Hook_OnGameOver(Event event, const char[] name, bool dontBroadcast) {
	if (IsLowPlayerCount()) {
		char nextmap[MAP_NAME_LENGTH];
		FindConVar("sm_nextmap").GetString(nextmap, sizeof(nextmap));
		if (IsSuitableBotMap(nextmap)) {
			return;
		}
		
		OverrideNextMapForBot(nextmap, sizeof(nextmap));
		
		LogMessage("Not many active players.  Changing next map to %s for bot support.", nextmap);
		
		GetMapDisplayName(nextmap, nextmap, sizeof(nextmap));
		
		PrintToChatAll("Server's pretty empty.  Changing the next map to %s so the bots keep playing.", nextmap);
	}
}

public Action Hook_OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if (!event.GetBool("bot") && IsLowPlayerCount() && !IsCurrentMapSuitable()
			&& !BotChangeMapTimerExists()) {
		float flSecondsToNextMap = g_ConVarDurationFromDisconnect.FloatValue;
		int nSecondsToNextMap = RoundToFloor(flSecondsToNextMap);
		PrintToServer("Server has emptied.  Attempt to change map in %d seconds...", nSecondsToNextMap);
		
		PrintToChatAll("Looks like the server emptied out!  " ...
				"If not enough people join, we'll switch to a bot-supported map in %d seconds.", nSecondsToNextMap);
		CreateBotChangeMapTimer(flSecondsToNextMap);
	}
}

public Action Hook_OnPlayerSpawn(Event event, const char[] name, bool dontBroadcast) {
	// TODO make it notify once
	if (GetGameTime() < g_flServerMapTriggerTime && IsLowPlayerCount() && !IsCurrentMapSuitable()) {
		int client = GetClientOfUserId(event.GetInt("userid"));
		
		int nSecondsToSwitch = RoundToCeil(g_flServerMapTriggerTime - GetGameTime());
		
		// TODO language files
		PrintToChat(client, "We'll switch to a bot-supported map in %d seconds if nobody joins.  Sit tight!", nSecondsToSwitch);
	}
}

public Action Timer_ChangeMap(Handle timer) {
	// Recheck to make sure the server's still dead before switching out
	// If another timer was created with a different time, use that instead
	if (RoundToFloor(GetGameTime()) >= RoundToFloor(g_flServerMapTriggerTime) && IsLowPlayerCount()) {
		char nextmap[MAP_NAME_LENGTH];
		
		int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
		g_ValidBotMaps.GetString(choice, nextmap, sizeof(nextmap));
		
		ForceChangeLevel(nextmap, "No active players; changed to a bot-playable map.");
	}
	return Plugin_Handled;
}

public Action Timer_AdminCmdBotMap(Handle timer) {
	char nextmap[MAP_NAME_LENGTH];
	
	int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
	g_ValidBotMaps.GetString(choice, nextmap, sizeof(nextmap));
	
	ForceChangeLevel(nextmap, "sm_botmap command");
	return Plugin_Handled;
}

void GenerateBotMapLists() {
	char map[MAP_NAME_LENGTH];
	
	// Check if this map was already allowed (in case we switched map cycles)
	GetCurrentMap(map, sizeof(map));
	
	/**
	 * Remember, IsSuitableBotMap checks the g_ValidBotMaps list;
	 * clearing it before checking would be bad.
	 * 
	 * ... I keep forgetting that's a thing that would happen.
	 */
	if (IsSuitableBotMap(map)) {
		g_ValidBotMaps.Clear();
		g_ValidBotMaps.PushString(map);
	} else {
		g_ValidBotMaps.Clear();
	}
	
	ArrayList includedBotMaps = new ArrayList(MAP_NAME_LENGTH);
	ArrayList excludedBotMaps = new ArrayList(MAP_NAME_LENGTH);
	
	GetExcludeMapList(excludedBotMaps);
	
	ParseOverrides(includedBotMaps, excludedBotMaps);
	
	// Resolve map names
	for (int i = 0; i < includedBotMaps.Length; i++) {
		includedBotMaps.GetString(i, map, sizeof(map));
		FindMap(map, map, sizeof(map));
		
		includedBotMaps.SetString(i, map);
	}
	
	for (int i = 0; i < excludedBotMaps.Length; i++) {
		excludedBotMaps.GetString(i, map, sizeof(map));
		FindMap(map, map, sizeof(map));
		
		excludedBotMaps.SetString(i, map);
	}
	
	ArrayList mapList = new ArrayList(MAP_NAME_LENGTH);
	if (ReadMapList(mapList) != INVALID_HANDLE) {
		for (int i = 0; i < mapList.Length; i++) {
			mapList.GetString(i, map, sizeof(map));
			
			#if defined _steamtools_included
			// fix for workshop unavailability
			if (!Steam_IsConnected() && StrContains(map, "workshop/") == 0) {
				continue;
			}
			#endif
			
			/**
			 * Current stable *does* have map resolving capabilities.
			 * It's not listed in the API, though...
			 */
			FindMapResult mapAvailability = FindMap(map, map, sizeof(map));
			
			if (includedBotMaps.FindString(map) > -1 ||
					(excludedBotMaps.FindString(map) == -1 && MapHasNavigationMesh(map)) ) {
				g_ValidBotMaps.PushString(map);
			}
		}
	}
	
	// TODO add all bot-supported maps if the pool is too small
	
	delete mapList;
	delete includedBotMaps;
	delete excludedBotMaps;
	
	LogMessage("%d maps currently available for bots to play on.", g_ValidBotMaps.Length);
}

void CreateBotChangeMapTimer(float interval) {
	g_flServerMapTriggerTime = GetGameTime() + interval;
	CreateTimer(interval, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
}

/**
 * Returns true if there is a timer set to check the server for deadness.
 */
bool BotChangeMapTimerExists() {
	return g_flServerMapTriggerTime > GetGameTime();
}

/**
 * Returns whether or not the next map was overwritten.
 * If bForce is true, then the next map is always overwritten (unless there are no valid maps).
 */
bool OverrideNextMapForBot(char[] nextmap, int length, bool bForce = true) {
	bool bNextMapSet = GetNextMap(nextmap, length);
	FindMapResult mapFind = FindMap(nextmap, nextmap, length);
	
	if (!bNextMapSet || mapFind == FindMap_NotFound || !IsSuitableBotMap(nextmap) || bForce) {
		int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
		g_ValidBotMaps.GetString(choice, nextmap, length);
		
		SetNextMap(nextmap);
		
		return true;
	}
	
	return false;
}

bool IsSuitableBotMap(const char[] map) {
	char mapName[MAP_NAME_LENGTH];
	FindMap(map, mapName, sizeof(mapName));
	
	return g_ValidBotMaps.FindString(mapName) > -1;
}

bool IsCurrentMapSuitable() {
	char currentmap[MAP_NAME_LENGTH];
	GetCurrentMap(currentmap, sizeof(currentmap));
	
	return IsSuitableBotMap(currentmap);
}

/**
 * On a low playercount, warns all players if the next map does not support bots.
 */
public void OnNextMapChanged(ConVar convar, const char[] oldValue, const char[] newValue) {
	if (!IsSuitableBotMap(newValue) && IsLowPlayerCount()) {
		PrintToChatAll("The next map does not support bots.\n"
				... "(In the event the server remains empty, the map will automatically be changed to one that does.)");
	}
}

/**
 * Returns true if the human player count is below the minimum threshold; we should consider switching maps.
 * If the threshold is at 1, that means the server must be empty before a map is changed.
 */
bool IsLowPlayerCount() {
	// TODO extended support
	return GetLivePlayerCount() < GetPlayerCountThreshold();
}

/**
 * Returns the player count threshold, reading from sm_bot_quota or tf_bot_quota if not set to a number.
 */
int GetPlayerCountThreshold() {
	char thresholdValue[8];
	g_ConVarPlayerCountThreshold.GetString(thresholdValue, sizeof(thresholdValue));
	
	int nPlayerThreshold;
	if (StrEqual(thresholdValue, "quota", false)) {
		// The Bot Manager plugin is prioritized over the built-in bot quota.
		ConVar conVarBotQuota = FindConVar("sm_bot_quota");
		
		if (conVarBotQuota != null) {
			nPlayerThreshold = conVarBotQuota.IntValue;
		} else {
			conVarBotQuota = FindConVar("tf_bot_quota");
			ConVar conVarQuotaMode = FindConVar("tf_bot_quota_mode");
			
			char quotaMode[8];
			conVarQuotaMode.GetString(quotaMode, sizeof(quotaMode));
			
			if (!StrEqual(quotaMode, "match")) {
				nPlayerThreshold = conVarBotQuota.IntValue;
			} else {
				// If you're matching, then I guess you always want bots to run.
				nPlayerThreshold = MaxClients;
			}
		}
	} else {
		nPlayerThreshold = g_ConVarPlayerCountThreshold.IntValue;
	}
	return nPlayerThreshold > 1 ? nPlayerThreshold : 1;
}

/**
 * Returns true if the given map has a corresponding navigation mesh file.
 * (This does not check inside maps, and it only strictly checks by filename.)
 */
bool MapHasNavigationMesh(const char[] map) {
	char navFilePath[PLATFORM_MAX_PATH];
	Format(navFilePath, sizeof(navFilePath), "maps/%s.nav", map);
	
	/**
	 * TODO check current map for navmesh; if exists (i.e., mesh exists inside map file), and
	 * not excluded, then add to separate list and store list on plugin unload.
	 */
	
	return FileExists(navFilePath, true);
}

void ParseOverrides(ArrayList includedMaps, ArrayList excludedMaps) {
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, PLATFORM_MAX_PATH, OVERRIDE_MAPLIST);
	
	if (FileExists(filePath)) {
		File overrideReader = OpenFile(filePath, "r");
		
		if (overrideReader != null) {
			// expect a + or -, a space, and the map name for overrides
			char line[MAP_NAME_LENGTH + 2];
			
			while (overrideReader.ReadLine(line, sizeof(line))) {
				TrimString(line);
				
				if (strlen(line) < 3 || FindCharInString(line, ' ') != 1) {
					continue;
				} else if (FindCharInString(line, '+') == 0) {
					// TODO make sure this is a valid map?
					includedMaps.PushString(line[2]);
				} else if (FindCharInString(line, '-') == 0) {
					excludedMaps.PushString(line[2]);
				} 
				// else ignore
			}
			
			delete overrideReader;
		}
	}
}

/**
 * Returns the number of players that are currently on a playing team.
 */
int GetLivePlayerCount() {
	int nPlayers;
	for (int i = MaxClients; i > 0; --i) {
		if (IsClientInGame(i) && !IsFakeClient(i) && view_as<TFTeam>(GetClientTeam(i)) != TFTeam_Spectator) {
			nPlayers++;
		}
	}
	return nPlayers;
}

int GetConnectingPlayerCount() {
	return GetClientCount(false) - GetClientCount(true);
}
