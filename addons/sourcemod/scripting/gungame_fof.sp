/**
 * vim: set ts=4 :
 * =============================================================================
 * Gun Game for Fistful of Frags
 *
 * Copyright 2021 Crimsontautology
 * =============================================================================
 *
 */

#pragma semicolon 1
#pragma newdecls required

#define PLUGIN_VERSION "1.10.0"
#define PLUGIN_NAME "[FoF] Gun Game"

#include <sourcemod>
#include <sdkhooks>

public Plugin myinfo =
{
	name = PLUGIN_NAME,
	author = "CrimsonTautology",
	description = "Gun Game for Fistful of Frags",
	version = PLUGIN_VERSION,
	url = "https://github.com/CrimsonTautology/sm-gungame-fof"
};

#define MAX_KEY_LENGTH 128

//TODO dropped equip_delay, drunkness, logfile
//TODO hook into fof_sv_dm_timer_ends_map, mp_bonusroundtime
//ConVar g_EnabledCvar;
//ConVar g_ConfigFileCvar;
//ConVar g_HealAmountCvar;
//ConVar g_AllowFistsCvar;
//ConVar g_AllowSuicidesCvar;

public void OnPluginStart()
{
    CreateConVar("gg_version", PLUGIN_VERSION, PLUGIN_NAME,
            FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    /*
    g_EnabledCvar = CreateConVar(
            "gg_enabled",
            "1",
            "Whether or not Gun Game is enabled");

    g_ConfigFileCvar = CreateConVar(
            "gg_config_file",
            "gungame_weapons.txt",
            _,
            0);

    g_HealAmountCvar = CreateConVar(
            "gg_heal_amount",
            "25", 
            "Amount of health to restore on each kill.",
            FCVAR_NOTIFY, true, 0.0);

    g_AllowFistsCvar = CreateConVar(
            "gg_allow_fists",
            "1",
            "Allow or disallow fists.",
            FCVAR_NOTIFY, true, 0.0, true, 1.0);

    g_AllowSuicidesCvar = CreateConVar(
            "gg_allow_suicides",
            "1",
            "Set 0 to disallow suicides, level down for it.",
            FCVAR_NOTIFY);
            */
    // hook events
    HookEvent("player_spawn", Event_PlayerSpawn );
    HookEvent("player_death", Event_PlayerDeath );
    HookEvent("round_start", Event_RoundStart);
    HookEvent("round_end", Event_RoundEnd);

    // handle late load
    for (int client = 1; client <= MaxClients; client++)
    {
        AddHooksToClient(client);
    }
}

public void OnPluginEnd()
{
    WriteLog("OnPluginEnd - cleanup; allow round to end");
    //g_GameState.AllowMapToEnd(true);
}

public void OnConfigsExecuted()
{
    WriteLog("OnConfigsExecuted: SetGameDescription, SetDefaultConVars, LoadGunGameFile");

    //SetGameDescription(GAME_DESCRIPTION);
    //g_GameState.AllowMapEnd(false);
}

public void OnMapStart()
{
    WriteLog("OnMapStart: DefaultGamestate; DefaultClients; PrecacheSound; Hook GetPlayerResourceEntity()");
    //delete g_WeaponList;
    //g_WeaponList = LoadGunGameFile(g_File);
    //RemoveCrates
}

public void OnClientPutInServer(int client)
{
    WriteLog("OnClientPutInServer %L: add hooks to client; Initialize", client);
    AddHooksToClient(client);
}

public void OnClientDisconnect(int client)
{
    WriteLog("OnClientDisconnect %L; ClearClient; RecalculateScore", client);
}

void Event_PlayerSpawn(Event event, const char[] name, bool dontBroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    WriteLog("PlayerSpawn %L; give weapons next frame", client);
}

void Event_PlayerDeath(Event event, const char[] name, bool dontBroadcast)
{
    int userid = GetEventInt(event, "userid");
    int client = GetClientOfUserId(userid);
    WriteLog("PlayerDeath %L; ", client);
}

void Event_RoundStart(Event event, const char[] name, bool dontBroadcast)
{
    WriteLog("RoundStart; cleanup? set game state");
}

void Event_RoundEnd(Event event, const char[] name, bool dontBroadcast)
{
    WriteLog("RoundEnd; set game state");
}

Action Hook_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype)
{
    // TODO no use
    WriteLog("OnTakeDamage %L <= %L", victim, attacker);

    return Plugin_Continue;
}

Action Hook_OnWeaponCanUse(int client, int weapon)
{
    //TODO need another check; on player give?  Can still get weapon from crate
    char class[MAX_KEY_LENGTH];
    GetEntityClassname(weapon, class, sizeof(class));
    WriteLog("OnWeaponCanUse %L <= %d(%s)", client, weapon, class);

    return Plugin_Continue;
}

Action Hook_OnWeaponCanSwitchTo(int client, int weapon)
{
    char class[MAX_KEY_LENGTH];
    GetEntityClassname(weapon, class, sizeof(class));
    WriteLog("--OnWeaponCanSwitchTo %L <= %d(%s)", client, weapon, class);

    return Plugin_Continue;
}

Action Hook_OnWeaponDrop(int client, int weapon)
{
    char class[MAX_KEY_LENGTH];
    GetEntityClassname(weapon, class, sizeof(class));
    WriteLog("--OnWeaponDrop %L <= %d(%s)", client, weapon, class);

    return Plugin_Continue;
}

Action Hook_OnWeaponEquip(int client, int weapon)
{
    char class[MAX_KEY_LENGTH];
    GetEntityClassname(weapon, class, sizeof(class));
    WriteLog("--OnWeaponEquip %L <= %d(%s)", client, weapon, class);

    return Plugin_Continue;
}

// Gun Game                                                 Zombies
// -----------------------------------------------------------------------------
// public void OnClientDisconnect_Post(int client) {}       public void OnClientDisconnect(int client)
//      \> RecalcScores
//                                                          public void OnClientPostAdminCheck(int client)
//      \> use OnClientPutInServer ?
// public void OnConfigsExecuted() {}                       public void OnConfigsExecuted()
//      \> SetGameDescription; DefaultConvars; LoadGunGameFile?
// public void OnMapStart() {}                              public void OnMapStart()
// public void OnPluginEnd() {}
// -----------------------------------------------------------------------------
// HookEvent("player_activate", Event_PlayerActivate);
//      \> move to OnClientPostAdminCheck
// HookEvent("player_death", Event_PlayerDeath);            HookEvent("player_death", Event_PlayerDeath);
//      \> handle level up; humiliation
// HookEvent("player_shoot", Event_PlayerShoot);
//      \> get LastWeaponFired -> handle "blast" death explosive 
// HookEvent("player_spawn", Event_PlayerSpawn);            HookEvent("player_spawn", Event_PlayerSpawn);
//      \> get first spawn StartTime; Timer_UpdateEquipment -> PlayerSpawnDelay
//                                                          HookEvent("player_team", Event_PlayerTeam, EventHookMode_Pre);
//                                                          HookEvent("round_end", Event_RoundEnd);
//      \> SetRoundState(RoundEnd);
// HookEvent("round_start", Event_RoundStart);              HookEvent("round_start", Event_RoundStart);
//      \> SetRoundState(RoundStart);
// -----------------------------------------------------------------------------
//                                                          AddCommandListener(Command_JoinTeam, "jointeam");
// -----------------------------------------------------------------------------
// SDKHook(_, SDKHook_OnTakeDamage, Hook_OnTakeDamage);     SDKHook(_, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
//      \> only used for post round gimick
// SDKHook(_, SDKHook_ThinkPost, Hook_OnPlayerResourceThinkPost);
//                                                          SDKHook(_, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
// SDKHook(_, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
//      \> CanUse might be a better event to hook


// Event_PlayerActivate( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast ) {}
// Event_PlayerSpawn( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast ) {}
// Event_PlayerShoot( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast ) {}
// Event_PlayerDeath( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast ) {}
// Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast) {}

// Action Hook_OnTakeDamage( iVictim, &iAttacker, &iInflictor, &Float:flDamage, &iDmgType, &iWeapon, Float:vecDmgForce[3], Float:vecDmgPosition[3], iDmgCustom ) {}
// Hook_WeaponSwitchPost( iClient, iWeapon ) {}
// Hook_OnPlayerResourceThinkPost(ent) {}

//TODO RequestFrame
// Action Timer_GetDrunk( Handle:hTimer, any:iUserID ) {}
// Action Timer_AllowMapEnd( Handle:hTimer, any:iUserID ) {}
// Action Timer_RespawnPlayers( Handle:hTimer ) {}
// Action Timer_RespawnPlayers_Fix( Handle:hTimer ) {}
// Action Timer_UpdateEquipment( Handle:hTimer, any:iUserID ) {}
// Action Timer_GiveWeapon( Handle:hTimer, Handle:hPack ) {}
// Action Timer_UseWeapon( Handle:hTimer, Handle:hPack ) {}
// Action Timer_SetAmmo( Handle:hTimer, Handle:hPack ) {}

// Action Timer_RespawnAnnounce( Handle:hTimer, any:iUserID ) {}
// Action Timer_Announce( Handle:hTimer, any:iUserID ) {}
//      \> Drop this

//TODO 1 second repeat
// Action Timer_Repeat(Handle:timer) {}

//TODO drop these
// public void OnConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] ) {}
// public void OnCfgConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] ) {}
// public void OnVerConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] ) {}

//TODO fof_gungame_restart/fof_gungame_reload_cfg -> sm_reloadgungame
// Action Command_RestartRound(int client, int args) {}
// Action Command_ReloadConfigFile(int client, int args) {}

//TODO what is this?
// Action Command_item_dm_end(int client, int args) {}


// util
// void RemoveCrate() {}
// void ReloadGunGameFromFile() {}
// Action Command_DumpScores(caller, args)

// stock _ShowHudText( iClient, Handle:hHudSynchronizer = INVALID_HANDLE, const String:szFormat[], any:... ) {}
// stock UseWeapon( iClient, const String:szItem[] ) {}
// stock SetAmmo( iClient, iWeapon, iAmmo ) //TODO does not work in FOF
// stock KillEdict( iEdict ) {}
// stock StripWeapons( iClient ) {}
// stock RestartTheGame() {}
// stock AllowMapEnd( bool:bState ) {}
// stock LeaderCheck( bool:bShowMessage = true ) {}
// stock bool SetGameDescription(String:description[]) {}
// stock WriteLog( const String:szFormat[], any:... ) {}
// stock Int32Max( iValue1, iValue2 ) {}
// stock float FloatMax( Float:flValue1, Float:flValue2 ) {}

//TODO
//float drunkness = GetEntPropFloat(client, Prop_Send, "m_flDrunkness");
//SetEntPropFloat(client, Prop_Send, "m_flDrunkness", drunkness);
//int score = GetEntProp(client, Prop_Send, "m_nLastRoundNotoriety");
//int frags = GetEntProp(client, Prop_Data, "m_iFrags"),
//int deaths = GetEntProp(client, Prop_Data, "m_iDeaths"),
//SetEntProp(client, Prop_Send, "m_nLastRoundNotoriety", iPlayerLevel[client]); //NOTE does not work
//int ragdoll_ent = GetEntPropEnt(client, Prop_Send, "m_hRagdoll");
//SetEntPropEnt(client, Prop_Send, "m_hRagdoll", INVALID_ENT_REFERENCE);

//int my_weapons_offset = FindSendPropInfo("CBasePlayer","m_hMyWeapons");
//int ammo_offset = FindSendPropInfo("CFoF_Player", "m_iAmmo");
//int ammo_type = GetEntProp(weapon_ent, Prop_Send, "m_iPrimaryAmmoType");
//SetEntData(client, ammo_offset + ammo_type * 4, weapon_ent);
//int weapon_ent = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
//int weapon2_ent = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon2");
//int weapon_ent = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", i);
//SetEntPropEnt(client, Prop_Send, "m_hMyWeapons", INVALID_ENT_REFERENCE, i);
//int weapon_ent = GivePlayerItem(client, weapon);
//RemovePlayerItem(client, weapon_ent);

//stock extSetActiveWeapon(client, weapon) {
//    SetEntPropEnt(client, Prop_Data, "m_hActiveWeapon", weapon);
//    ChangeEdictState(client, FindDataMapOffs(client, "m_hActiveWeapon"));
//}
//   Just remember that if you remove the weapon first then switch to the
//   new weapon with this method then it will not show the view model.


//SetEntProp(ent, Prop_Send, "m_iExp", level, _, client); //PlayerResource
//SetEntProp(ent, Prop_Send, "m_iScore", score, _, client); //PlayerResource




void AddHooksToClient(int client)
{
    if (!IsClientInGame(client)) return;

    WriteLog("AddHooksToClient %L", client);

    SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
    SDKHook(client, SDKHook_WeaponCanUse, Hook_OnWeaponCanUse);
    SDKHook(client, SDKHook_WeaponEquip, Hook_OnWeaponEquip);
    SDKHook(client, SDKHook_WeaponDrop, Hook_OnWeaponDrop);

    SDKHook(client, SDKHook_WeaponCanSwitchTo, Hook_OnWeaponCanSwitchTo);
    //SDKHook(client, SDKHook_WeaponSwitch, Hook_OnWeaponSwitch);
}


stock void WriteLog(const char[] format, any ...)
{
#if defined DEBUG
    char buf[2048];
    VFormat(buf, sizeof(buf), format, 2);
    PrintToServer("[GG - %.3f] %s", GetGameTime(), buf);
#endif
}
