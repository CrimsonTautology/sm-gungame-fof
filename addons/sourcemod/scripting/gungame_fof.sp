/**
 * vim: set ts=4 :
 * =============================================================================
 * Gun Game for Fistful of Frags
 *
 * Copyright 2021 CrimsonTautology
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION "1.10.0"
#define PLUGIN_NAME "[FoF] Gun Game"
#define CHAT_PREFIX "\x04 GG \x07FFDA00 "
#define CONSOLE_PREFIX "[GunGame] "

#define GAME_DESCRIPTION "Gun Game"
#define SOUND_LEVELUP "music/bounty/bounty_objective_stinger1.mp3"
#define SOUND_FINAL "music/bounty/bounty_objective_stinger2.mp3"
#define SOUND_ROUNDWON "music/round_end_stinger.mp3"
#define SOUND_HUMILIATION "animals/chicken_pain1.wav"
#define SOUND_LOSTLEAD "music/most_wanted_stinger.wav"
#define SOUND_TAKENLEAD "halloween/ragged_powerup.wav"
#define SOUND_TIEDLEAD "music/kill3.wav"

new String:g_RoundStartSounds[][] =
{
    "common/defeat.mp3",
    "common/victory.mp3",
    "music/standoff1.mp3",
};

#define HUD1_X 0.18
#define HUD1_Y 0.04

#define HUD2_X 0.18
#define HUD2_Y 0.10

new Handle:fof_gungame_config = INVALID_HANDLE;
new Handle:fof_gungame_fists = INVALID_HANDLE;
new Handle:fof_gungame_equip_delay = INVALID_HANDLE;
new Handle:fof_gungame_heal = INVALID_HANDLE;
new Handle:fof_gungame_drunkness = INVALID_HANDLE;
new Handle:fof_gungame_suicides = INVALID_HANDLE;
new Handle:fof_gungame_logfile = INVALID_HANDLE;
new Handle:fof_sv_dm_timer_ends_map = INVALID_HANDLE;
new Handle:mp_bonusroundtime = INVALID_HANDLE;

new bool:g_AllowFists = false;
new Float:g_EquipDelay = 0.0;
new g_HealAmount = 25;
new Float:g_DrunknessAmount = 2.5;
new bool:g_AllowSuicides = false;
new String:g_LogFilePath[PLATFORM_MAX_PATH];
new Float:g_BonusRoundTime = 5.0;

new Handle:g_HUDSync1 = INVALID_HANDLE;
new Handle:g_HUDSync2 = INVALID_HANDLE;
new Handle:g_WeaponsTable = INVALID_HANDLE;
new g_AmmoOffset = -1;
new g_WinningClient = 0;
new String:g_WinningClientName[MAX_NAME_LENGTH];
new g_LeadingClient = 0;
new g_MaxLevel = 1;

new g_ClientLevel[MAXPLAYERS+1];
new bool:g_UpdateEquipment[MAXPLAYERS+1];
new Float:g_LastKill[MAXPLAYERS+1];
new Float:g_LastLevelUP[MAXPLAYERS+1];
new Float:g_LastUse[MAXPLAYERS+1];
new bool:g_WasInGame[MAXPLAYERS+1];
new String:g_LastWeaponFired[MAXPLAYERS+1][32];
new bool:g_FirstEquip[MAXPLAYERS+1];
new bool:g_FirstSpawn[MAXPLAYERS+1];
new Float:g_StartTime[MAXPLAYERS+1];
new bool:g_IsInTheLead[MAXPLAYERS+1];
new bool:g_WasInTheLead[MAXPLAYERS+1];

new Handle:g_Timer_GiveWeapon1[MAXPLAYERS+1] = {INVALID_HANDLE, ...};
new Handle:g_Timer_GiveWeapon2[MAXPLAYERS+1] = {INVALID_HANDLE, ...};

new bool:g_AutoSetGameDescription = false;

public Plugin:myinfo =
{
    name = "[FoF] Gun Game",
    author = "CrimsonTautology, Leonardo",
    description = "Gun Game for Fistful of Frags",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm-gungame-fof"
};

public OnPluginStart()
{
    CreateConVar("fof_gungame_version", PLUGIN_VERSION, PLUGIN_NAME,
            FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    CreateConVar("fof_gungame_enabled", "0", _, FCVAR_NOTIFY, true, 0.0, true, 1.0);
    HookConVarChange(fof_gungame_config = CreateConVar("fof_gungame_config", "gungame_weapons.txt", _, 0), OnCfgConVarChanged);
    HookConVarChange(fof_gungame_fists = CreateConVar("fof_gungame_fists", "1", "Allow or disallow fists.", FCVAR_NOTIFY, true, 0.0, true, 1.0), OnConVarChanged);
    HookConVarChange(fof_gungame_equip_delay = CreateConVar("fof_gungame_equip_delay", "0.0", "Seconds before giving new equipment.", FCVAR_NOTIFY, true, 0.0), OnConVarChanged);
    HookConVarChange(fof_gungame_heal = CreateConVar("fof_gungame_heal", "25", "Amount of health to restore on each kill.", FCVAR_NOTIFY, true, 0.0), OnConVarChanged);
    HookConVarChange(fof_gungame_drunkness = CreateConVar("fof_gungame_drunkness", "6.0", _, FCVAR_NOTIFY), OnConVarChanged);
    HookConVarChange(fof_gungame_suicides = CreateConVar("fof_gungame_suicides", "1", "Set 0 to disallow suicides, level down for it.", FCVAR_NOTIFY), OnConVarChanged);
    HookConVarChange(fof_gungame_logfile = CreateConVar("fof_gungame_logfile", "", _, 0), OnConVarChanged);
    fof_sv_dm_timer_ends_map = FindConVar("fof_sv_dm_timer_ends_map");
    HookConVarChange(mp_bonusroundtime = FindConVar("mp_bonusroundtime"), OnConVarChanged);
    AutoExecConfig();

    HookEvent("player_activate", Event_PlayerActivate);
    HookEvent("player_spawn", Event_PlayerSpawn);
    HookEvent("player_shoot", Event_PlayerShoot);
    HookEvent("player_death", Event_PlayerDeath);
    HookEvent("round_start", Event_RoundStart);

    RegAdminCmd("fof_gungame_restart", Command_RestartRound, ADMFLAG_GENERIC);
    RegAdminCmd("fof_gungame_reload_cfg", Command_ReloadConfigFile, ADMFLAG_CONFIG);
    RegAdminCmd("fof_gungame_scores", Command_DumpScores, ADMFLAG_ROOT, "[DEBUG] List player score values");
    AddCommandListener(Command_item_dm_end, "item_dm_end");

    g_HUDSync1 = CreateHudSynchronizer();
    g_HUDSync2 = CreateHudSynchronizer();

    g_AmmoOffset = FindSendPropInfo("CFoF_Player", "m_iAmmo");

    g_WeaponsTable = CreateKeyValues("gungame_weapons");

    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            SDKHook(i, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            SDKHook(i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        }
    }

}

public OnPluginEnd()
{
    AllowMapEnd(true);
}

public OnClientDisconnect_Post(client)
{
    //if(g_WinningClient == client) g_WinningClient = 0;

    new timeleft;
    if(GetMapTimeLeft(timeleft) && timeleft > 0 && g_WinningClient <= 0)
        LeaderCheck();

    g_ClientLevel[client] = 0;
}

public OnMapStart()
{
    new Handle:mp_teamplay = FindConVar("mp_teamplay");
    new Handle:fof_sv_currentmode = FindConVar("fof_sv_currentmode");
    if(mp_teamplay != INVALID_HANDLE && fof_sv_currentmode != INVALID_HANDLE)
    {
        //TODO ?
        // no-op
    }
    else
    {
        SetFailState("Missing mp_teamplay or/and fof_sv_currentmode console variable");
    }

    g_WinningClient = 0;
    g_WinningClientName[0] = '\0';
    g_LeadingClient = 0;
    g_MaxLevel = 1;
    for(new i = 0; i < sizeof(g_ClientLevel); i++)
    {
        g_ClientLevel[i] = 1;
        g_LastKill[i] = 0.0;
        g_LastLevelUP[i] = 0.0;
        g_LastUse[i] = 0.0;
        g_StartTime[i] = 0.0;
        g_WasInTheLead[i] = false;
        g_IsInTheLead[i] = false;
    }

    PrecacheSound(SOUND_LEVELUP, true);
    PrecacheSound(SOUND_FINAL, true);
    PrecacheSound(SOUND_ROUNDWON, true);
    PrecacheSound(SOUND_HUMILIATION, true);
    PrecacheSound(SOUND_LOSTLEAD, true);
    PrecacheSound(SOUND_TAKENLEAD, true);
    PrecacheSound(SOUND_TIEDLEAD, true);
    for(new i=0; i < sizeof(g_RoundStartSounds); i++)
    {
        PrecacheSound(g_RoundStartSounds[i]);
    }

    g_AutoSetGameDescription = true;
    CreateTimer(1.0, Timer_Repeat, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);

    SDKHook(GetPlayerResourceEntity(), SDKHook_ThinkPost, Hook_OnPlayerResourceThinkPost);
}

void RemoveCrates()
{
    new ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "fof_crate*")) != INVALID_ENT_REFERENCE)
    {
        AcceptEntityInput(ent, "Kill");
    }
}

public OnConfigsExecuted()
{
    SetGameDescription(GAME_DESCRIPTION);

    AllowMapEnd(false);

    ScanConVars();
    ReloadConfigFile();
}

void ScanConVars()
{
    g_AllowFists = GetConVarBool(fof_gungame_fists);
    g_EquipDelay = FloatMax(0.0, GetConVarFloat(fof_gungame_equip_delay));
    g_HealAmount = Int32Max(0, GetConVarInt(fof_gungame_heal));
    g_DrunknessAmount = GetConVarFloat(fof_gungame_drunkness);
    g_AllowSuicides = GetConVarBool(fof_gungame_suicides);
    GetConVarString(fof_gungame_logfile, g_LogFilePath, sizeof(g_LogFilePath));
    g_BonusRoundTime = FloatMax(0.0, GetConVarFloat(mp_bonusroundtime));
}

void ReloadConfigFile()
{
    g_MaxLevel = 1;

    new String:file[PLATFORM_MAX_PATH], String:nextlevel[16];
    GetConVarString(fof_gungame_config, file, sizeof(file));
    BuildPath(Path_SM, file, sizeof(file), "configs/%s", file);
    IntToString(g_MaxLevel, nextlevel, sizeof(nextlevel));

    if(g_WeaponsTable != INVALID_HANDLE)
        CloseHandle(g_WeaponsTable);
    g_WeaponsTable = CreateKeyValues("gungame_weapons");
    if(FileToKeyValues(g_WeaponsTable, file))
    {
        new String:levelName[16], level, String:playerWeapon[2][32];
        if(KvGotoFirstSubKey(g_WeaponsTable))
            do
            {
                KvGetSectionName(g_WeaponsTable, levelName, sizeof(levelName));

                if(!IsCharNumeric(levelName[0]))
                    continue;

                level = StringToInt(levelName);
                if(g_MaxLevel < level)
                    g_MaxLevel = level;

                if(KvGotoFirstSubKey(g_WeaponsTable, false))
                {
                    KvGetSectionName(g_WeaponsTable, playerWeapon[0], sizeof(playerWeapon[]));
                    KvGoBack(g_WeaponsTable);
                    KvGetString(g_WeaponsTable, playerWeapon[0], playerWeapon[1], sizeof(playerWeapon[]));
                }
                PrintToServer("%sLevel %d = %s%s%s", CONSOLE_PREFIX, g_MaxLevel, playerWeapon[0], playerWeapon[1][0] != '\0' ? ", " : "", playerWeapon[1]);
            }
            while(KvGotoNextKey(g_WeaponsTable));
        PrintToServer("%sTop level - %d", CONSOLE_PREFIX, g_MaxLevel);
    }
    else
        PrintToServer("%sFalied to parse the config file.", CONSOLE_PREFIX);
}

void OnConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    ScanConVars();
}

void OnCfgConVarChanged(Handle:convar, const String:oldValue[], const String:newValue[])
{
    ReloadConfigFile();
}

Action Command_RestartRound(client, args)
{
    RestartTheGame();
    return Plugin_Handled;
}

Action Command_ReloadConfigFile(client, args)
{
    ReloadConfigFile();
    return Plugin_Handled;
}

Action Command_item_dm_end(client, const String:command[], args)
{
    if(g_FirstEquip[client])
    {
        g_FirstEquip[client] = false;
        CreateTimer(0.0, Timer_UpdateEquipment, GetClientUserId(client), TIMER_FLAG_NO_MAPCHANGE);
    }
    return Plugin_Continue;
}

void Event_PlayerActivate(Handle:event, const String:eventname[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(0 < client <= MaxClients)
    {
        g_ClientLevel[ client ] = 1;
        g_LastKill[ client ] = 0.0;
        g_LastLevelUP[ client ] = 0.0;
        g_LastUse[ client ] = 0.0;
        g_FirstEquip[ client ] = true;
        g_FirstSpawn[ client ] = true;
        g_StartTime[ client ] = 0.0;
        if(IsClientInGame(client))
        {
            SDKHook(client, SDKHook_OnTakeDamage, Hook_OnTakeDamage);
            SDKHook(client, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost);
        }
    }
}

void Event_PlayerSpawn(Handle:event, const String:eventname[], bool:dontBroadcast)
{
    new userid = GetEventInt(event, "userid");
    new client = GetClientOfUserId(userid);

    if(0 < client <= MaxClients && g_FirstSpawn[client])
    {
        g_FirstSpawn[client] = false;
        g_StartTime[client] = GetGameTime();
        CreateTimer(2.0, Timer_Announce, userid, TIMER_FLAG_NO_MAPCHANGE);
    }

    CreateTimer(0.1, Timer_UpdateEquipment, userid, TIMER_FLAG_NO_MAPCHANGE);
}

void Event_PlayerShoot(Handle:event, const String:eventname[], bool:dontBroadcast)
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
    if(0 < client <= MaxClients)
    {
        GetEventString(event, "weapon", g_LastWeaponFired[client], sizeof(g_LastWeaponFired[]));
    }
}

void Event_PlayerDeath(Handle:event, const String:eventname[], bool:dontBroadcast)
{
    new victim = GetClientOfUserId(GetEventInt(event, "userid"));
    new killerUID = GetEventInt(event, "attacker");
    new killer = GetClientOfUserId(killerUID);
    new damagebits = GetClientOfUserId(GetEventInt(event, "damagebits"));

    if(damagebits & DMG_FALL)
        return;

    if(g_WinningClient > 0)
    {
        if(0 < victim <= MaxClients && IsClientInGame(victim))
            EmitSoundToClient(victim, SOUND_HUMILIATION);
        return;
    }

    if(victim == killer || killer == 0 && GetEventInt(event, "assist") <= 0)
    {
        if(!g_AllowSuicides && g_ClientLevel[killer] > 1)
        {
            g_ClientLevel[victim]--;
            LeaderCheck();

            PrintCenterText(victim, "Ungraceful death! You are now level %d of %d.", g_ClientLevel[victim], g_MaxLevel);
            PrintToChat(victim, "%sUngraceful death! You are now level %d of %d.", CHAT_PREFIX, g_ClientLevel[victim], g_MaxLevel);
            EmitSoundToClient(victim, SOUND_HUMILIATION);
        }
        return;
    }

    if(!(0 < killer <= MaxClients && IsClientInGame(victim) && IsClientInGame(killer)))
        return;

    new Float:timestamp = GetGameTime();
    if((timestamp - g_LastKill[killer]) < 0.01 || (timestamp - g_LastLevelUP[killer]) <= 0.0)
        return;
    g_LastKill[killer] = timestamp;

    new String:weapon_name[32];
    GetEventString(event, "weapon", weapon_name, sizeof(weapon_name));

    //Humiliate victim on fists kill by lowering their level
    if((StrEqual(weapon_name, "fists") ||  StrEqual(weapon_name, "kick-fall")) 
            && g_ClientLevel[victim] > 1 && 0 < killer <= MaxClients)
    {
        g_ClientLevel[victim]--;
        LeaderCheck();

        PrintCenterTextAll("%N was humiliated by %N and lost a level!", victim, killer);
        PrintToConsoleAll("%N was humiliated by %N and lost a level!", victim, killer);
        PrintToChat(victim, "%sHumiliating death! You are now level %d of %d.", CHAT_PREFIX, g_ClientLevel[victim], g_MaxLevel);
        EmitSoundToClient(victim, SOUND_HUMILIATION);
        EmitSoundToClient(killer, SOUND_HUMILIATION);
    }

    if(StrEqual(weapon_name, "arrow"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_bow");
    else if(StrEqual(weapon_name, "thrown_axe"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_axe");
    else if(StrEqual(weapon_name, "thrown_knife"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_knife");
    else if(StrEqual(weapon_name, "thrown_machete"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_machete");
    else if(StrEqual(weapon_name, "rpg_missile"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_rpg");
    else if(StrEqual(weapon_name, "crossbow_bolt"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_crossbow");
    else if(StrEqual(weapon_name, "grenade_ar2"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_ar2");
    else if(StrEqual(weapon_name, "weapon_ar2"))
        strcopy(weapon_name, sizeof(weapon_name), "weapon_ar2");
    else if(StrEqual(weapon_name, "blast"))
        strcopy(weapon_name, sizeof(weapon_name), g_LastWeaponFired[killer]);
    else
    {
        if(weapon_name[strlen(weapon_name)-1] == '2')
            weapon_name[strlen(weapon_name)-1] = '\0';
        Format(weapon_name, sizeof(weapon_name), "weapon_%s", weapon_name);
    }



    new String:playerLevel[16];
    IntToString(g_ClientLevel[killer], playerLevel, sizeof(playerLevel));

    new String:allowedWeapon[2][24];
    KvRewind(g_WeaponsTable);
    if(KvJumpToKey(g_WeaponsTable, playerLevel, false) && KvGotoFirstSubKey(g_WeaponsTable, false))
    {
        KvGetSectionName(g_WeaponsTable, allowedWeapon[0], sizeof(allowedWeapon[]));
        KvGoBack(g_WeaponsTable);
        KvGetString(g_WeaponsTable, allowedWeapon[0], allowedWeapon[1], sizeof(allowedWeapon[]));
        KvGoBack(g_WeaponsTable);
    }

    //PrintToConsole(killer, "%sKilled player with %s (required:%s%s%s)", CONSOLE_PREFIX, weapon_name, allowedWeapon[0], allowedWeapon[1][0] != '\0' ? "," : "", allowedWeapon[1]);

    if(allowedWeapon[0][0] == '\0' && allowedWeapon[1][0] == '\0')
    {
        LogError("Missing weapon for level %d!", g_ClientLevel[killer]);
        //return;
    }
    else if(!IsFakeClient(killer) && !StrEqual(weapon_name, allowedWeapon[0]) && !StrEqual(weapon_name, allowedWeapon[1]))
        return;

    g_LastLevelUP[killer] = timestamp + g_EquipDelay;
    g_ClientLevel[killer]++;
    if(g_ClientLevel[killer] > g_MaxLevel)
    {
        g_ClientLevel[killer] = g_MaxLevel;
        g_WinningClient = killer;
        GetClientName(killer, g_WinningClientName, sizeof(g_WinningClientName));

        new String:durationString[64], Float:duration = (GetGameTime() - g_StartTime[killer]);
        if(duration > 60.0)
        {
            new mins = 0;
            while(duration >= 60.0)
            {
                duration -= 60.0;
                mins++;
            }
            if(duration > 0.0)
                FormatEx(durationString, sizeof(durationString), "%d min. %.1f sec.", mins, duration); // TODO wow this is wrong
            else
                FormatEx(durationString, sizeof(durationString), "%d min.", mins);
        }
        else
            FormatEx(durationString, sizeof(durationString), " %.1f sec.", duration);

        PrintCenterTextAll("%N has won the round!", killer);
        PrintToChatAll("%sPlayer \x03%N\x07FFDA00 has won the round in \x03%s", CHAT_PREFIX, killer, durationString);
        PrintToServer("%sPlayer '%N' has won the round in %s", CONSOLE_PREFIX, killer, durationString);
        EmitSoundToAll(SOUND_ROUNDWON);

        for(new i = 1; i <= MaxClients; i++)
        {
            if(i != killer)
            {
                //g_ClientLevel[i] = 1;
                g_StartTime[i] = 0.0;
            }
            if(IsClientInGame(i))
                CreateTimer(0.0, Timer_UpdateEquipment, GetClientUserId(i), TIMER_FLAG_NO_MAPCHANGE);
        }

        CreateTimer(3.0, Timer_RespawnAnnounce, .flags = TIMER_FLAG_NO_MAPCHANGE);
        AllowMapEnd(true);
    }
    else if(g_ClientLevel[killer] == g_MaxLevel)
    {
        LeaderCheck(false);

        PrintCenterTextAll("%N is on the final weapon!", killer);
        PrintToConsoleAll("%sPlayer '%N' is on the final weapon!", CONSOLE_PREFIX, killer);
        EmitSoundToClient(killer, SOUND_FINAL);
    }
    else
    {
        LeaderCheck();

        PrintCenterText(killer, "Leveled up! You are now level %d of %d.", g_ClientLevel[killer], g_MaxLevel);
        PrintToConsole(killer, "%sLeveled up! You are now level %d of %d.", CONSOLE_PREFIX, g_ClientLevel[killer], g_MaxLevel);
        EmitSoundToClient(killer, SOUND_LEVELUP);
    }

    if(IsPlayerAlive(killer))
    {
        if(g_HealAmount != 0)
            SetEntityHealth(killer, GetClientHealth(killer) + g_HealAmount);
        CreateTimer(0.01, Timer_GetDrunk, killerUID, TIMER_FLAG_NO_MAPCHANGE);
    }

    CreateTimer(0.0, Timer_UpdateEquipment, killerUID, TIMER_FLAG_NO_MAPCHANGE);
}

Action Timer_GetDrunk(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);
    if(g_DrunknessAmount != 0.0 && 0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client))
        SetEntPropFloat(client, Prop_Send, "m_flDrunkness", FloatMax(0.0, GetEntPropFloat(client, Prop_Send, "m_flDrunkness") + g_DrunknessAmount));
    return Plugin_Stop;
}

void Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    RemoveCrates();

    //Clear scores
    g_WinningClient = 0;
    g_WinningClientName[0] = '\0';
    g_LeadingClient = 0;
    for(new i = 0; i < sizeof(g_ClientLevel); i++)
    {
        g_ClientLevel[i] = 1;
        g_LastKill[i] = 0.0;
        g_LastLevelUP[i] = 0.0;
        g_LastUse[i] = 0.0;
        g_StartTime[i] = 0.0;
        g_WasInTheLead[i] = false;
        g_IsInTheLead[i] = false;
    }
}

Action Hook_OnTakeDamage(int victim, int& attacker, int& inflictor, float& damage, int& damagetype, int& weapon, float damageForce[3], float damagePosition[3])
{
    if(0 < victim <= MaxClients && IsClientInGame(victim))
    {
        if(g_WinningClient > 0 && g_WinningClient == attacker)
        {
            damage = 300.0;
            damagetype |= DMG_CRUSH;
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}

void Hook_WeaponSwitchPost(client, weapon)
{
    if(client != g_WinningClient && 0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client))
    {
        WriteLog("Hook_WeaponSwitchPost(%d): %L", client, client);

        new String:playerLevel[16];
        IntToString(g_ClientLevel[client], playerLevel, sizeof(playerLevel));

        new String:allowedWeapon[2][24], Handle:AllowedWeapons = CreateArray(8);
        if(g_AllowFists)
        {
            WriteLog("Hook_WeaponSwitchPost(%d): adding weapon_fists", client);
            PushArrayString(AllowedWeapons, "weapon_fists");
        }
        if(g_WinningClient <= 0)
        {
            KvRewind(g_WeaponsTable);
            if(KvJumpToKey(g_WeaponsTable, playerLevel, false) && KvGotoFirstSubKey(g_WeaponsTable, false))
            {
                KvGetSectionName(g_WeaponsTable, allowedWeapon[0], sizeof(allowedWeapon[]));
                KvGoBack(g_WeaponsTable);
                if(allowedWeapon[0][0] != '\0')
                {
                    WriteLog("Hook_WeaponSwitchPost(%d): adding '%s'", client, allowedWeapon[0]);
                    PushArrayString(AllowedWeapons, allowedWeapon[0]);
                }

                KvGetString(g_WeaponsTable, allowedWeapon[0], allowedWeapon[1], sizeof(allowedWeapon[]));
                KvGoBack(g_WeaponsTable);
                if(allowedWeapon[1][0] != '\0')
                {
                    WriteLog("Hook_WeaponSwitchPost(%d): adding '%s'", client, allowedWeapon[1]);
                    PushArrayString(AllowedWeapons, allowedWeapon[1]);
                }
            }
        }

        new weapon_ent[2];
        weapon_ent[0] = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon");
        weapon_ent[1] = GetEntPropEnt(client, Prop_Send, "m_hActiveWeapon2");

        for(new String:class[32], i, w = 0; w < sizeof(weapon_ent); w++)
            if(weapon_ent[w] > MaxClients && IsValidEdict(weapon_ent[w]))
            {
                GetEntityClassname(weapon_ent[w], class, sizeof(class));
                if(class[strlen(class)-1] == '2')
                    class[strlen(class)-1] = '\0';
                if(StrContains(class, "weapon_") != 0)
                {
                    WriteLog("Hook_WeaponSwitchPost(%d): incorrect weapon '%s' (%s/%d)", client, class, w == 0 ? "m_hActiveWeapon" : "m_hActiveWeapon2", weapon_ent[w]);
                    continue;
                }

                if((i = FindStringInArray(AllowedWeapons, class)) >= 0)
                    RemoveFromArray(AllowedWeapons, i);
                else
                {
                    WriteLog("Hook_WeaponSwitchPost(%d): unacceptable '%s' (%s/%d)", client, class, w == 0 ? "m_hActiveWeapon" : "m_hActiveWeapon2", weapon_ent[w]);

                    RemovePlayerItem(client, weapon_ent[w]);
                    KillEdict(weapon_ent[w]);

                    UseWeapon(client, "weapon_fists");
                }
            }

        CloseHandle(AllowedWeapons);
        WriteLog("Hook_WeaponSwitchPost(%d): end", client);
    }
}

void Hook_OnPlayerResourceThinkPost(ent)
{
    new client, level, score;
    for(client = 1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client)) continue;

        level = Int32Max(g_ClientLevel[client], 0);
        score = GetEntProp(client, Prop_Send, "m_nLastRoundNotoriety");
        SetEntProp(ent, Prop_Send, "m_iExp", level, _, client);
        SetEntProp(ent, Prop_Send, "m_iScore", score, _, client);
        //SetEntProp(client, Prop_Send, "m_nLastRoundNotoriety", g_ClientLevel[client]);
    }

}

Action Timer_RespawnAnnounce(Handle:timer, any:userid)
{
    CreateTimer(g_BonusRoundTime, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE);
    CreateTimer(FloatMax(0.0, (g_BonusRoundTime - 1.0)), Timer_AllowMapEnd, .flags = TIMER_FLAG_NO_MAPCHANGE);
    if(g_BonusRoundTime >= 1.0)
        PrintToChatAll("%sStarting new round in %d seconds...", CHAT_PREFIX, RoundToCeil(g_BonusRoundTime));
    return Plugin_Stop;
}

Action Timer_AllowMapEnd(Handle:timer, any:userid)
{
    AllowMapEnd(true);
    return Plugin_Stop;
}

Action Timer_RespawnPlayers(Handle:timer)
{
    AllowMapEnd(true);

    g_WinningClient = 0;
    g_WinningClientName[0] = '\0';
    g_LeadingClient = 0;
    for(new i = 0; i < sizeof(g_ClientLevel); i++)
    {
        g_ClientLevel[i] = 1;
        g_LastKill[i] = 0.0;
        g_StartTime[i] = 0.0;
        g_WasInTheLead[i] = false;
        g_IsInTheLead[i] = false;
        g_WasInGame[i] = false;
        if(0 < i <= MaxClients && IsClientInGame(i))
        {
            g_UpdateEquipment[i] = true;
            g_WasInGame[i] = GetClientTeam(i) != 1;
            g_StartTime[i] = GetGameTime();
        }
    }

    CreateTimer(0.05, Timer_RespawnPlayers_Fix, .flags = TIMER_FLAG_NO_MAPCHANGE);

    if(GetCommandFlags("round_restart") != INVALID_FCVAR_FLAGS)
        ServerCommand("round_restart");

    new ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "weapon_*")) != INVALID_ENT_REFERENCE)
        AcceptEntityInput(ent, "Kill");
    ent = INVALID_ENT_REFERENCE;
    while((ent = FindEntityByClassname(ent, "dynamite*")) != INVALID_ENT_REFERENCE)
        AcceptEntityInput(ent, "Kill");

    for(new client = 1; client <= MaxClients; client++)
    {
        if(IsClientInGame(client))
        {
            KillEdict(GetEntPropEnt(client, Prop_Send, "m_hRagdoll"));
            SetEntPropEnt(client, Prop_Send, "m_hRagdoll", INVALID_ENT_REFERENCE);
        }
    }

    return Plugin_Stop;
}

Action Timer_RespawnPlayers_Fix(Handle:timer)
{
    AllowMapEnd(false);

    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(g_WasInGame[i] && GetClientTeam(i) == 1)
                FakeClientCommand(i, "autojoin");
            else if(g_WasInGame[i] && !IsPlayerAlive(i))
                PrintToServer("%sPlayer %L is still dead!", CONSOLE_PREFIX, i);
            else if(g_UpdateEquipment[i])
                Timer_UpdateEquipment(INVALID_HANDLE, GetClientUserId(i));
        }
    }

    new timeleft;
    if(GetMapTimeLeft(timeleft) && timeleft > 0)
        EmitSoundToAll(g_RoundStartSounds[GetRandomInt(0, sizeof(g_RoundStartSounds) - 1)]);

    return Plugin_Stop;
}

Action Timer_UpdateEquipment(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);
    if(!(0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)))
        return Plugin_Stop;

    g_UpdateEquipment[client] = false;

    if(g_WinningClient == client)
        SetEntityHealth(client, 500);
    else
    {
        UseWeapon(client, "weapon_fists");
        StripWeapons(client);
    }

    if(g_WinningClient > 0 && client != g_WinningClient)
    {
        WriteLog("Timer_GiveWeapon(%d): Updating the loadout. Level #%d, fists only (looser).", client, g_ClientLevel[client]);
    }
    else
    {
        new String:playerLevel[16];
        if(g_WinningClient > 0 && client == g_WinningClient)
            strcopy(playerLevel, sizeof(playerLevel), "winner");
        else
            IntToString(g_ClientLevel[client], playerLevel, sizeof(playerLevel));

        new String:playerWeapon[2][32];
        KvRewind(g_WeaponsTable);
        if(KvJumpToKey(g_WeaponsTable, playerLevel) && KvGotoFirstSubKey(g_WeaponsTable, false))
        {
            KvGetSectionName(g_WeaponsTable, playerWeapon[0], sizeof(playerWeapon[]));
            KvGoBack(g_WeaponsTable);
            KvGetString(g_WeaponsTable, playerWeapon[0], playerWeapon[1], sizeof(playerWeapon[]));
            KvGoBack(g_WeaponsTable);
            if(StrEqual(playerWeapon[0], playerWeapon[1]))
                Format(playerWeapon[1], sizeof(playerWeapon[]), "%s2", playerWeapon[0]);
        }

        if(playerWeapon[0][0] == '\0' && playerWeapon[1][0] == '\0')
        {
            if(client != g_WinningClient)
            {
                LogError("Missing weapon for level %d!", g_ClientLevel[client]);
                WriteLog("Timer_GiveWeapon(%d): Updating the loadout. Level #%d, fists only (missing loadout).", client, g_ClientLevel[client]);
            }
            return Plugin_Stop;
        }

        new Handle:pack1;
        //if(g_Timer_GiveWeapon1[client] != INVALID_HANDLE) CloseHandle(g_Timer_GiveWeapon1[client]);
        g_Timer_GiveWeapon1[client] = CreateDataTimer(g_EquipDelay + 0.05, Timer_GiveWeapon, pack1, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
        WritePackCell(pack1, userid);
        WritePackString(pack1, playerWeapon[0]);

        new Handle:pack2;
        //if(g_Timer_GiveWeapon2[client] != INVALID_HANDLE) CloseHandle(g_Timer_GiveWeapon2[client]);
        g_Timer_GiveWeapon2[client] = CreateDataTimer(g_EquipDelay + 0.18, Timer_GiveWeapon, pack2, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
        WritePackCell(pack2, userid);
        WritePackString(pack2, playerWeapon[1]);

        WriteLog("Timer_GiveWeapon(%d): Updating the loadout. Level #%d, weapon1: '%s', weapon2: '%s'%s.", client, g_ClientLevel[client], playerWeapon[0], playerWeapon[1], client == g_WinningClient ? " (winner)" : "");
    }

    return Plugin_Stop;
}

Action Timer_GiveWeapon(Handle:timer, Handle:pack)
{
    ResetPack(pack);

    new userid = ReadPackCell(pack);
    new client = GetClientOfUserId(userid);

    //TODO FIXME
    //g_Timer_GiveWeapon1[client] = INVALID_HANDLE;
    //g_Timer_GiveWeapon2[client] = INVALID_HANDLE;

    if(!(0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)))
        return Plugin_Stop;

    new String:weapon_name[32];
    ReadPackString(pack, weapon_name, sizeof(weapon_name));
    if(weapon_name[0] == '\0')
        return Plugin_Stop;

    WriteLog("Timer_GiveWeapon(%d): %L", client, client);

    new weapon;
    if((weapon = GivePlayerItem(client, weapon_name)) > MaxClients)
    {
        WriteLog("Timer_GiveWeapon(%d): generated %s/%d", client, weapon_name, weapon);

        if(StrContains(weapon_name, "weapon_dynamite") == 0)
            SetAmmo(client, weapon, 100);
        else if(StrEqual(weapon_name, "weapon_knife"))
            SetAmmo(client, weapon, 2);
        else if(StrEqual(weapon_name, "weapon_axe") || StrEqual(weapon_name, "weapon_machete"))
            SetAmmo(client, weapon, 1);

        new Handle:pack1;
        CreateDataTimer(0.1, Timer_UseWeapon, pack1, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
        WritePackCell(pack1, userid);
        WritePackString(pack1, weapon_name);
    }
    else
    {
        WriteLog("Timer_GiveWeapon(%d): failed to generate '%s'", client, weapon_name);
        LogError("Failed to generate %s", weapon_name);
    }

    WriteLog("Timer_GiveWeapon(%d): end", client);
    return Plugin_Stop;
}

Action Timer_UseWeapon(Handle:timer, Handle:pack)
{
    ResetPack(pack);

    new client = GetClientOfUserId(ReadPackCell(pack));
    if(!(0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)))
        return Plugin_Stop;

    new String:weapon_name[32];
    ReadPackString(pack, weapon_name, sizeof(weapon_name));
    if(weapon_name[0] == '\0')
        return Plugin_Stop;

    UseWeapon(client, weapon_name);
    return Plugin_Stop;
}

Action Timer_Repeat(Handle:timer)
{
    //NOTE: game is automatically changing game description; use same method as
    //fistful of zombies to set it back.
    if (g_AutoSetGameDescription)
    {
        SetGameDescription(GAME_DESCRIPTION);
        g_AutoSetGameDescription = false;
    }

    //update hud
    //TODO move this to .inc
    new topLevel = 0, clients[MaxClients+1], numClients = 0;
    if(g_WinningClient <= 0)
    {
        for(new i = 1; i <= MaxClients; i++)
            if(IsClientInGame(i) && g_ClientLevel[i] > topLevel)
                topLevel = g_ClientLevel[i];

        for(new i = 1; i <= MaxClients; i++)
            if(IsClientInGame(i) && g_ClientLevel[i] >= topLevel && GetClientTeam(i) != 1)
                clients[numClients++] = i;
    }

    for(new i = 1; i <= MaxClients; i++)
        if(IsClientInGame(i))
        {
            ClearSyncHud(i, g_HUDSync1);
            ClearSyncHud(i, g_HUDSync2);

            if(g_WinningClient > 0)
            {
                if(numClients == g_WinningClient)
                {
                    SetHudTextParams(HUD1_X, HUD1_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync1, "YOU ARE THE WINNER");
                }
                else
                {
                    SetHudTextParams(HUD1_X, HUD1_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync1, "WINNER:");

                    SetHudTextParams(HUD2_X, HUD2_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync1, "%s", g_WinningClientName);
                }
            }
            else if(numClients == 1 && clients[0] == i && GetClientTeam(i) != 1)
            {
                SetHudTextParams(HUD1_X, HUD1_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0);
                _ShowHudText(i, g_HUDSync1, "THE LEADER");

                if(g_ClientLevel[i] >= g_MaxLevel)
                {
                    SetHudTextParams(HUD2_X, HUD2_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync2, "LEVEL: FINAL");
                }
                else
                {
                    SetHudTextParams(HUD2_X, HUD2_Y, 1.125, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync2, "LEVEL: %d", g_ClientLevel[i]);
                }
            }
            else
            {
                if(topLevel >= g_MaxLevel)
                {
                    SetHudTextParams(HUD1_X, HUD1_Y, 1.125, 220, 120, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync1, "LEADER: FINAL LVL");
                }
                else
                {
                    SetHudTextParams(HUD1_X, HUD1_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync1, "LEADER: %d LVL", topLevel);
                }

                if(GetClientTeam(i) == 1)
                    continue;

                if(g_ClientLevel[i] >= g_MaxLevel)
                {
                    SetHudTextParams(HUD2_X, HUD2_Y, 1.15, 0, 250, 0, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync2, "YOU: FINAL LVL");
                }
                else
                {
                    SetHudTextParams(HUD2_X, HUD2_Y, 1.15, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0);
                    _ShowHudText(i, g_HUDSync2, "YOU: %d LVL", g_ClientLevel[i]);
                }
            }
        }
    return Plugin_Handled;
}

Action Timer_Announce(Handle:timer, any:userid)
{
    new client = GetClientOfUserId(userid);
    if(0 < client <= MaxClients && IsClientInGame(client))
        PrintToChat(client, "\x07FF0000WARNING:\x07FFDA00 This is an unofficial game mode made by \x03XPenia Team\x07FFDA00.");
    return Plugin_Stop;
}

void _ShowHudText(client, Handle:hud = INVALID_HANDLE, const String:format[], any:...)
{
    if(0 < client <= MaxClients && IsClientInGame(client))
    {
        //WriteLog("_ShowHudText(%d): %L", client, client);

        new String:buffer[250];
        VFormat(buffer, sizeof(buffer), format, 4);

        if(ShowHudText(client, -1, buffer) < 0 && hud != INVALID_HANDLE)
        {
            //WriteLog("_ShowHudText(%d): ShowSyncHudText(%d, %08X, '%s')", client, client, hud, buffer);
            ShowSyncHudText(client, hud, buffer);
        }

        //WriteLog("_ShowHudText(%d): end", client);
    }
}

void UseWeapon(client, const String:item[])
{
    if(0 < client <= MaxClients && IsClientInGame(client))
    {
        WriteLog("UseWeapon(%d): %L", client, client);
        if(IsPlayerAlive(client))
        {
            new Float:timestamp = GetGameTime();
            if((timestamp - g_LastUse[client]) >= 0.1)
            {
                new bool:wasFound = false;
                for(new weapon, String:class[32], s = 0; s < 48; s++)
                    if(IsValidEdict((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", s))))
                    {
                        GetEntityClassname(weapon, class, sizeof(class));
                        //if(class[strlen(class)-1] == '2')
                        //  class[strlen(class)-1] = '\0';
                        if(StrEqual(class, item))
                        {
                            //EquipPlayerWeapon(client, weapon);
                            wasFound = true;
                            break;
                        }
                    }
                if(wasFound)
                {
                    WriteLog("UseWeapon(%d): use %s", client, item);
                    FakeClientCommandEx(client, "use %s", item);
                    g_LastUse[client] = timestamp;
                }
            }
            else
            {
                WriteLog("UseWeapon(%d): %f < 0.1 (item:%s)", client, (timestamp - g_LastUse[client]), item);
            }
        }
        else
        {
            WriteLog("UseWeapon(%d): client is dead (item:%s)", client, item);
        }
        WriteLog("UseWeapon(%d): end", client);
    }
}

void SetAmmo(client, weapon, ammo)
{
    if(0 < client <= MaxClients && IsClientInGame(client))
    {
        new Handle:pack;
        CreateDataTimer(0.1, Timer_SetAmmo, pack, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE);
        WritePackCell(pack, GetClientUserId(client));
        WritePackCell(pack, EntIndexToEntRef(weapon));
        WritePackCell(pack, ammo);
    }
}
Action Timer_SetAmmo(Handle:timer, Handle:pack)
{
    ResetPack(pack);

    if(g_AmmoOffset <= 0)
        return Plugin_Stop;

    new client = GetClientOfUserId(ReadPackCell(pack));
    if(!(0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client)))
        return Plugin_Stop;

    new weapon = EntRefToEntIndex(ReadPackCell(pack));
    if(weapon <= MaxClients || !IsValidEdict(weapon))
        return Plugin_Stop;

    SetEntData(client, g_AmmoOffset + GetEntProp(weapon, Prop_Send, "m_iPrimaryAmmoType") * 4, ReadPackCell(pack));
    return Plugin_Stop;
}

void KillEdict(edict)
{
    if(edict > MaxClients && IsValidEdict(edict))
    {
        WriteLog("KillEdict: AcceptEntityInput(%d, \"Kill\")", edict);
        AcceptEntityInput(edict, "Kill");
    }
}

void StripWeapons(client)
{
    if(0 < client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client))
    {
        WriteLog("StripWeapons(%d): %L", client, client);
        for(new weapon, bool:wasFound, weapons[48], String:class[32], s = 0; s < 48; s++)
        {
            wasFound = false;
            class[0] = '\0';
            if(IsValidEdict((weapon = GetEntPropEnt(client, Prop_Send, "m_hMyWeapons", s))))
            {
                for(new w = 0; w < sizeof(weapons); w++)
                    if(weapons[w] == weapon)
                    {
                        wasFound = true;
                        WriteLog("StripWeapons(%d): found duplicate '%s' (slot:%d,entity:%d)", client, class, s, weapon);
                    }
                if(wasFound)
                    continue;
                for(new w = 0; w < sizeof(weapons); w++)
                    if(weapons[w] <= MaxClients)
                    {
                        weapons[w] = weapon;
                        break;
                    }
                GetEntityClassname(weapon, class, sizeof(class));
                if(g_AllowFists && StrEqual(class, "weapon_fists"))
                {
                    WriteLog("StripWeapons(%d): skipping '%s' (slot:%d,entity:%d)", client, class, s, weapon);
                    continue;
                }
                else
                {
                    WriteLog("StripWeapons(%d): removing '%s' (slot:%d,entity:%d)", client, class, s, weapon);
                    RemovePlayerItem(client, weapon);
                    SetEntPropEnt(client, Prop_Send, "m_hMyWeapons", INVALID_ENT_REFERENCE, s);
                    KillEdict(weapon);
                }
            }
        }
        WriteLog("StripWeapons(%d): end", client);
    }
}

void RestartTheGame()
{
    CreateTimer(0.0, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE);

    PrintCenterTextAll("GUNGAME HAS BEEN RESTARTED!");
    PrintToChatAll("%sThe game has been restarted!", CHAT_PREFIX);
}

void AllowMapEnd(bool:can_end)
{
    if(fof_sv_dm_timer_ends_map != INVALID_HANDLE)
    {
        SetConVarBool(fof_sv_dm_timer_ends_map, can_end, false, false);
    }
}

int LeaderCheck(bool:canShowMessage = true)
{
    new topLevel = 1, leaders = 0, oldLeader = g_LeadingClient;

    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            g_WasInTheLead[i] = g_IsInTheLead[i];
            if(g_ClientLevel[i] > topLevel)
            {
                topLevel = g_ClientLevel[i];
            }
        }
        g_IsInTheLead[i] = false;
    }

    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i) && g_ClientLevel[i] >= topLevel && GetClientTeam(i) != 1)
        {
            g_IsInTheLead[i] = true;
            g_LeadingClient = ((++leaders) == 1 ? i : 0);
        }
    }

    for(new i = 1; i <= MaxClients; i++)
    {
        if(IsClientInGame(i))
        {
            if(g_IsInTheLead[i] && (!g_WasInTheLead[i] || oldLeader == i) && leaders > 1)
            {
                EmitSoundToClient(i, SOUND_TIEDLEAD, .flags = SND_CHANGEPITCH, .pitch = 115);
                if(canShowMessage)
                    PrintToConsoleAll("%s'%N' is also in the lead (level %d)", CONSOLE_PREFIX, i, g_ClientLevel[i]);
            }
            else if(g_IsInTheLead[i] && oldLeader != g_LeadingClient && g_LeadingClient == i)
            {
                EmitSoundToClient(i, SOUND_TAKENLEAD, .flags = SND_CHANGEPITCH, .pitch = 115);
                if(canShowMessage)
                {
                    PrintCenterTextAll("%N is in the lead", i, g_ClientLevel[i]);
                    PrintToConsoleAll("%s'%N' is in the lead (level %d)", CONSOLE_PREFIX, i, g_ClientLevel[i]);
                }
            }
            else if(!g_IsInTheLead[i] && g_WasInTheLead[i])
                EmitSoundToClient(i, SOUND_LOSTLEAD);
        }
    }

    return leaders;
}

bool SetGameDescription(String:description[])
{
#if defined _SteamWorks_Included
    return SteamWorks_SetGameDescription(description);
#else
    return false;
#endif
}

stock WriteLog(const String:format[], any:...)
{
#if defined DEBUG
    if(g_LogFilePath[0] != '\0' && format[0] != '\0')
    {
        decl String:buffer[2048];
        VFormat(buffer, sizeof(buffer), format, 2);
        LogToFileEx(g_LogFilePath, "[%.3f] %s", GetGameTime(), buffer);
        //PrintToServer("[%.3f] %s", GetGameTime(), buffer);
    }
#endif
}

int Int32Max(value1, value2)
{
    return value1 > value2 ? value1 : value2;
}

float FloatMax(Float:value1, Float:value2)
{
    return FloatCompare(value1, value2) >= 0 ? value1 : value2;
}

Action Command_DumpScores(caller, args)
{
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "Leader: %d", g_LeadingClient);
    PrintToConsole(caller, "---------------------------------");
    PrintToConsole(caller, "level notoriety frags deaths user");
    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client) || IsFakeClient(client))
            continue;

        PrintToConsole(caller, "%5d %9d %5d %6d %L",
                g_ClientLevel[client],
                GetEntProp(client, Prop_Send, "m_nLastRoundNotoriety"),
                GetEntProp(client, Prop_Data, "m_iFrags"),
                GetEntProp(client, Prop_Data, "m_iDeaths"),
                client);
    }
    PrintToConsole(caller, "---------------------------------");
    return Plugin_Handled;
}
