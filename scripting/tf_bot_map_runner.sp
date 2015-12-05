/**
 * This is an updated version of the old "[TF2] Bot-only Map Override" plugin.
 */
#pragma semicolon 1

#include <sourcemod>
#include <mapchooser>
#include <tf2>

#pragma newdecls required

#define PLUGIN_VERSION "0.1.1"
public Plugin myinfo = {
	name = "[TF2] Bot Map Runner",
	author = "nosoop",
	description = "Forces the server to cycle through maps with bot support when the player count is too low. #botsrights",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFBotMapRunner"
}

#define MAP_NAME_LENGTH 96
#define OVERRIDE_MAPLIST "configs/bot_map_runner.txt"

ArrayList g_ValidBotMaps, g_ExcludedBotMaps, g_IncludedBotMaps;

public void OnPluginStart() {
	LoadTranslations("mapchooser.phrases");
	
	RegAdminCmd("sm_botmap", AdminCmd_BotMap, ADMFLAG_CHANGEMAP, "Immediately changes to a bot-compatible map.");
	RegAdminCmd("sm_setnextbotmap", AdminCmd_SetNextBotMap, ADMFLAG_CHANGEMAP, "Changes the next map to a bot-compatible map.");
	
	RegAdminCmd("sm_botmap_refresh", AdminCmd_RefreshMapList, ADMFLAG_CHANGEMAP, "Refreshes the bot map list.");
	
	HookEvent("teamplay_game_over", Hook_OnGameOver, EventHookMode_PostNoCopy);
	HookEvent("player_disconnect", Hook_OnPlayerDisconnect, EventHookMode_Post);
	
	g_ValidBotMaps = new ArrayList(MAP_NAME_LENGTH);
	g_IncludedBotMaps = new ArrayList(MAP_NAME_LENGTH);
	g_ExcludedBotMaps = new ArrayList(MAP_NAME_LENGTH);
}

public void OnMapStart() {
	GenerateBotMapLists();
	
	// TODO playercount detection because it doesn't include connecting clients
	if (IsLowPlayerCount() && !IsCurrentMapSuitable()) {
		// TODO make sure that the map exclusion doesn't include the current map
		PrintToServer("No players detected.  Changing map in 1.5 minutes...");
		CreateTimer(90.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action AdminCmd_BotMap(int client, int nArgs) {
	ShowActivity(client, "Changing to a bot supported map...");
	CreateTimer(5.0, Timer_ForceChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
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
		OverrideNextMapForBot(nextmap, sizeof(nextmap));
		
		LogMessage("Not many active players.  Changing next map to %s for bot support.", nextmap);
		PrintToChatAll("Server's pretty empty.  Changing the next map to %s so the bots keep playing.", nextmap);
	}
}

public Action Hook_OnPlayerDisconnect(Event event, const char[] name, bool dontBroadcast) {
	if (!event.GetBool("bot") && IsLowPlayerCount() && !IsCurrentMapSuitable()) {
		PrintToServer("Server has emptied.  Changing map in 1.5 minutes...");
		CreateTimer(90.0, Timer_ChangeMap, _, TIMER_FLAG_NO_MAPCHANGE);
	}
}

public Action Timer_ChangeMap(Handle timer) {
	// Recheck to make sure the server's still dead before switching out
	if (IsLowPlayerCount()) {
		char nextmap[MAP_NAME_LENGTH];
		
		int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
		g_ValidBotMaps.GetString(choice, nextmap, sizeof(nextmap));
		
		ForceChangeLevel(nextmap, "No active players; changed to a bot-playable map.");
	}
	return Plugin_Handled;
}

public Action Timer_ForceChangeMap(Handle timer) {
	char nextmap[MAP_NAME_LENGTH];
	
	int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
	g_ValidBotMaps.GetString(choice, nextmap, sizeof(nextmap));
	
	ForceChangeLevel(nextmap, "Map overridden for bot support.");
	return Plugin_Handled;
}

void GenerateBotMapLists() {
	g_ValidBotMaps.Clear();
	g_ExcludedBotMaps.Clear();
	g_IncludedBotMaps.Clear();
	
	GetExcludeMapList(g_ExcludedBotMaps);
	
	ParseOverrides();
	
	char map[MAP_NAME_LENGTH];
	ArrayList mapList = new ArrayList(MAP_NAME_LENGTH);
	if (ReadMapList(mapList) != INVALID_HANDLE) {
		for (int i = 0; i < mapList.Length; i++) {
			mapList.GetString(i, map, sizeof(map));
			
			// TODO resolve map names when 1.8 hits stable
			// Right now, it doesn't support Workshop maps unless manually included.
			
			if (IsSuitableBotMap(map)) {
				g_ValidBotMaps.PushString(map);
			}
		}
	}
	delete mapList;
	
	LogMessage("%d maps currently available for bots to play on.", g_ValidBotMaps.Length);
}

/**
 * Returns whether or not the next map was overwritten.
 * If bForce is true, then the next map is always overwritten (unless there are no valid maps).
 */
bool OverrideNextMapForBot(char[] nextmap, int length, bool bForce = true) {
	bool bNextMapSet = GetNextMap(nextmap, length);
	
	if (!bNextMapSet || !IsSuitableBotMap(nextmap) || bForce) {
		int choice = GetRandomInt(0, g_ValidBotMaps.Length-1);
		g_ValidBotMaps.GetString(choice, nextmap, length);
		
		SetNextMap(nextmap);
		
		return true;
	}
	
	// if not a valid map then throw error "map doesn't exist"
	
	return false;
}

bool IsSuitableBotMap(const char[] map) {
	return MapIncluded(map) || (!MapExcluded(map) && MapHasNavigationMesh(map));
}

bool IsCurrentMapSuitable() {
	char currentmap[MAP_NAME_LENGTH];
	GetCurrentMap(currentmap, sizeof(currentmap));
	
	return IsSuitableBotMap(currentmap);
}

/**
 * Returns true if the human player count is low enough to consider overriding the next map.
 */
bool IsLowPlayerCount() {
	// TODO extended support
	return GetLivePlayerCount() < 2;
}

/**
 * Returns true if the given map has been excluded from the bot map list, even if it has a
 * valid navigation mesh.  Useful for Halloween maps that have navmeshes tailored for bots.
 * 
 * The list of excluded maps also includes maps that were recently played.
 */
bool MapExcluded(const char[] map) {
	return (g_ExcludedBotMaps.FindString(map) > -1);
}

/**
 * Returns true if the given map has been included in the bot map list.	 Useful for maps that
 * contain embedded navigation meshes, as we can't find that out through
 * MapHasNavigationMesh().
 * 
 * Do note that only maps in the full map list will be added to the potential bot maps,
 * regardless of whether or not it's been added to the override list.
 */
bool MapIncluded(const char[] map) {
	return (g_IncludedBotMaps.FindString(map) > -1);
}

/**
 * Returns true if the given map has a corresponding navigation mesh file.
 * (This does not check inside maps, and it only strictly checks by filename.)
 */
bool MapHasNavigationMesh(const char[] map) {
	char navFilePath[PLATFORM_MAX_PATH];
	Format(navFilePath, sizeof(navFilePath), "maps/%s.nav", map);
	
	return FileExists(navFilePath, true);
}

void ParseOverrides() {
	char filePath[PLATFORM_MAX_PATH];
	BuildPath(Path_SM, filePath, PLATFORM_MAX_PATH, OVERRIDE_MAPLIST);
	
	if (FileExists(filePath)) {
		File overrideReader = OpenFile(filePath, "r");
		
		if (overrideReader != null) {
			char line[MAP_NAME_LENGTH + 2]; // + or -, a space, and the map name
			
			while (overrideReader.ReadLine(line, sizeof(line))) {
				TrimString(line);
				
				if (strlen(line) < 2) {
					continue;
				} else if (FindCharInString(line, '+') == 0) {
					g_IncludedBotMaps.PushString(line[2]);
				} else if (FindCharInString(line, '-') == 0) {
					g_ExcludedBotMaps.PushString(line[2]);
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
