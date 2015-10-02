/**
 * vim: set ts=4 :
 * =============================================================================
 * Gun Game FoF
 * Updated version of Leonardo's Fistful of Frags Gun Game plugin.
 *
 * =============================================================================
 *
 */

#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION      "2.0"
#define PLUGIN_NAME         "[FoF] Gun Game"

#define MAX_WEAPON_LEVELS   128
#define MAX_WEAPON_NAME_SIZE 32

#define BASE_LEVEL 1

#if !defined IN_FOF_SWITCH
#define IN_FOF_SWITCH   (1<<14)
#endif

#define SOUND_STINGER1  "music/bounty/bounty_objective_stinger1.mp3"
#define SOUND_STINGER2  "music/bounty/bounty_objective_stinger2.mp3"
#define SOUND_FIGHT  "vehicles/train/whistle.wav"
#define SOUND_HUMILIATION  "vehicles/train/whistle.wav"
#define SOUND_LOSTLEAD  "vehicles/train/whistle.wav"
#define SOUND_TAKENLEAD  "vehicles/train/whistle.wav"
#define SOUND_TIEDLEAD  "vehicles/train/whistle.wav"



new Handle:g_Cvar_Enabled = INVALID_HANDLE;
new Handle:g_Cvar_Config = INVALID_HANDLE;
new Handle:g_Cvar_Fists = INVALID_HANDLE;
new Handle:g_Cvar_Heal = INVALID_HANDLE;
new Handle:g_Cvar_Drunkness = INVALID_HANDLE;
new Handle:g_Cvar_Suicides = INVALID_HANDLE;
new Handle:fof_sv_dm_timer_ends_map = INVALID_HANDLE;

//TODO clean this up; there are way too many globals
new Handle:g_HUD_Leader = INVALID_HANDLE;
new Handle:g_HUD_Level = INVALID_HANDLE;
new iAmmoOffset = -1;

new g_MaxLevel;
new g_ClientLevel[MAXPLAYERS+1];

new bool:bUpdateEquipment[MAXPLAYERS+1];
new Float:flLastKill[MAXPLAYERS+1];
new Float:flLastLevelUP[MAXPLAYERS+1];
new Float:flLastUse[MAXPLAYERS+1];
new bool:bWasInGame[MAXPLAYERS+1];
new String:szLastWeaponFired[MAXPLAYERS+1][32];
new bool:bFirstEquip[MAXPLAYERS+1];
new bool:bFirstSpawn[MAXPLAYERS+1];
new Float:flStart[MAXPLAYERS+1];
new bool:bInTheLead[MAXPLAYERS+1];
new bool:bWasInTheLead[MAXPLAYERS+1];

//Weaponlist for each level;  second array is for any secondary weapon
new String:g_WeaponLevelList[MAX_WEAPON_LEVELS][MAX_WEAPON_NAME_SIZE];
new String:g_WeaponLevelListAlt[MAX_WEAPON_LEVELS][MAX_WEAPON_NAME_SIZE];

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "Leonardo, Modified by CrimsonTautology",
    description = "Gun Game for Fistful of Frags",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_gungame_fof"
};

public OnPluginStart()
{
    CreateConVar("fof_gungame_version", PLUGIN_VERSION, PLUGIN_NAME, FCVAR_PLUGIN | FCVAR_SPONLY | FCVAR_REPLICATED | FCVAR_NOTIFY | FCVAR_DONTRECORD);

    g_Cvar_Enabled = CreateConVar(
            "fof_gungame_enabled",
            "1",
            _,
            FCVAR_PLUGIN | FCVAR_REPLICATED | FCVAR_NOTIFY,
            true,
            0.0,
            true,
            1.0);

    g_Cvar_Config = CreateConVar(
            "fof_gungame_config",
            "gungame_weapons.txt",
            _,
            FCVAR_PLUGIN);

    g_Cvar_Fists = CreateConVar(
            "fof_gungame_fists",
            "1",
            "Allow or disallow fists.",
            FCVAR_PLUGIN|FCVAR_NOTIFY,
            true,
            0.0,
            true,
            1.0);

    g_Cvar_Heal = CreateConVar(
            "fof_gungame_heal",
            "25",
            "Amount of health to restore on each kill.",
            FCVAR_PLUGIN|FCVAR_NOTIFY,
            true,
            0.0);

    g_Cvar_Drunkness = CreateConVar(
            "fof_gungame_drunkness",
            "6.0",
            _,
            FCVAR_PLUGIN|FCVAR_NOTIFY);

    g_Cvar_Suicides = CreateConVar(
            "fof_gungame_suicides",
            "1",
            "Set 0 to disallow suicides, level down for it.",
            FCVAR_PLUGIN|FCVAR_NOTIFY);

    AutoExecConfig();


    HookEvent( "player_activate", Event_PlayerActivate );
    HookEvent( "player_spawn", Event_PlayerSpawn );
    HookEvent( "player_shoot", Event_PlayerShoot );
    //HookEvent( "player_death", Event_PlayerDeath_Pre, EventHookMode_Pre );
    HookEvent( "player_death", Event_PlayerDeath );

    RegAdminCmd( "sm_restartround", Command_RestartRound, ADMFLAG_GENERIC );
    RegAdminCmd( "sm_reloadgungame", Command_ReloadGungame, ADMFLAG_CONFIG );

    AddCommandListener( Command_item_dm_end, "item_dm_end" );

    g_HUD_Leader = CreateHudSynchronizer();
    g_HUD_Level = CreateHudSynchronizer();

    iAmmoOffset = FindSendPropInfo( "CFoF_Player", "m_iAmmo" );

    for( new i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame( i ) )
        {
            SDKHook( i, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
            SDKHook( i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost );
        }
    }

    RestartTheGame();

    HookEntityOutput( "logic_auto", "OnMapSpawn", Output_OnMapSpawn );
}

public OnPluginEnd()
{
}

public OnClientDisconnect_Post(client)
{
}

public OnMapStart()
{
    PrecacheSound( SOUND_STINGER1, true );
    PrecacheSound( SOUND_STINGER2, true );
    PrecacheSound( SOUND_FIGHT, true );
    PrecacheSound( SOUND_HUMILIATION, true );
    PrecacheSound( SOUND_LOSTLEAD, true );
    PrecacheSound( SOUND_TAKENLEAD, true );
    PrecacheSound( SOUND_TIEDLEAD, true );
}

public Output_OnMapSpawn( const String:szOutput[], iCaller, iActivator, Float:flDelay )
{
    new iCrate = INVALID_ENT_REFERENCE;
    while( ( iCrate = FindEntityByClassname( iCrate, "fof_crate*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iCrate, "Kill" );
}

public OnConfigsExecuted()
{
    SetGameDescription("Gun Game", true);

    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadConfigFile(file, g_MaxLevel, g_WeaponLevelList, g_WeaponLevelListAlt);

}

LoadConfigFile(String:file[], &max_level, String:weapon_level_list[][], String:weapon_level_list_alt[][])
{
    max_level = BASE_LEVEL;

    new String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);

    new Handle:weapons = CreateKeyValues( "gungame_weapons" );

    if(!FileToKeyValues(weapons, path))
    {
        LogError("Could not read Gun Game config file \"%s\"", path);
        SetFailState("Could not read Gun Game config file \"%s\"", path);
        CloseHandle(weapons);
        return;
    }

    new String:tmp[16], level;

    KvGotoFirstSubKey(weapons);

    do
    {
        KvGetSectionName(weapons, tmp, sizeof(tmp));

        //Skip non-level keys
        if(!IsCharNumeric(tmp[0]))
            continue;

        level = StringToInt(tmp);

        if(max_level < level) max_level = level;

        if(KvGotoFirstSubKey(weapons, false ))
        {
            //The way this was stored originally was to have the key be the primary weapon and the value to be the altnerate weapon (if one exists)
            KvGetSectionName(weapons, weapon_level_list[level], MAX_WEAPON_NAME_SIZE);
            KvGoBack(weapons);
            KvGetString(weapons, weapon_level_list[level], weapon_level_list_alt[level], MAX_WEAPON_NAME_SIZE);
        }

        PrintToServer( "Level %d = %s%s%s", level, weapon_level_list[level], weapon_level_list_alt[level][0] != '\0' ? ", " : "", weapon_level_list_alt[level]);
    }
    while(KvGotoNextKey(weapons));

    PrintToServer( "Top level - %d", max_level );

    CloseHandle(weapons);
}

public Action:Command_RestartRound( client, nArgs )
{
    RestartTheGame();

    return Plugin_Handled;
}

public Action:Command_ReloadGungame( client, nArgs )
{
    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadConfigFile(file, g_MaxLevel, g_WeaponLevelList, g_WeaponLevelListAlt);

    //TODO
    PrintWeaponLevelLists(g_MaxLevel, g_WeaponLevelList, g_WeaponLevelListAlt);

    return Plugin_Handled;
}

public Action:Command_item_dm_end( client, const String:szCommand[], nArgs )
{
    //TODO what is this?
    return Plugin_Continue;
}

public Event_PlayerActivate(Handle:event, const String:name[], bool:dontBroadcast)
{
    //TODO when is this called?
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
}

public Event_PlayerSpawn(Handle:event, const String:name[], bool:dontBroadcast)
{
    if(!IsGungameEnabled()) return;

    new player = GetEventInt(event, "userid");
    CreateTimer( 0.0, PlayerSpawnDelay, player, TIMER_FLAG_NO_MAPCHANGE );
}

public Action:PlayerSpawnDelay(Handle:timer, any:player)
{
    if(!IsGungameEnabled()) return Plugin_Handled;

    new client = GetClientOfUserId(player);

    if(client <= 0) return Plugin_Handled;
    if(!IsClientInGame(client)) return Plugin_Handled;
    if(!IsPlayerAlive(client)) return Plugin_Handled;

    new level = GetClientLevel(client);
    StripInvalidWeapons(client, g_WeaponLevelList[level], g_WeaponLevelListAlt[level]);

    return Plugin_Handled;
}

public Action:Event_PlayerDeath_Pre(Handle:event, const String:name[], bool:dontBroadcast )
{
    new victim = GetClientOfUserId(GetEventInt( event, "userid"));
    return Plugin_Continue;
}

public Event_PlayerShoot( Handle:event, const String:name[], bool:dontBroadcast )
{
    new client = GetClientOfUserId(GetEventInt(event, "userid"));
}

public Event_PlayerDeath( Handle:event, const String:name[], bool:dontBroadcast )
{
    new iVictim = GetClientOfUserId( GetEventInt(event, "userid"));
    new iKillerUID = GetEventInt(event, "attacker");
    new iKiller = GetClientOfUserId( iKillerUID);
    new iDmgBits = GetClientOfUserId( GetEventInt(event, "damagebits"));

}

public Action:Timer_GetDrunk( Handle:hTimer, any:iUserID )
{
    //Make own method
    new client = GetClientOfUserId( iUserID );
    new Float:drunkness = GetConVarFloat(g_Cvar_Drunkness);

    if(drunkness > 0.0 && 0 < client <= MaxClients && IsClientInGame( client ) && IsPlayerAlive( client ) )
        SetEntPropFloat( client, Prop_Send, "m_flDrunkness", GetEntPropFloat( client, Prop_Send, "m_flDrunkness" ) + drunkness);
    return Plugin_Stop;
}

public Action:Hook_OnTakeDamage( iVictim, &iAttacker, &iInflictor, &Float:flDamage, &iDmgType, &iWeapon, Float:vecDmgForce[3], Float:vecDmgPosition[3], iDmgCustom )
{
    return Plugin_Continue;
}

public Hook_WeaponSwitchPost( client, iWeapon )
{
    //TODO may not be needed
}

public Action:Timer_RespawnAnnounce( Handle:hTimer, any:iUserID )
{
    return Plugin_Stop;
}

public Action:Timer_AllowMapEnd( Handle:hTimer, any:iUserID )
{
    AllowMapEnd( true );
    return Plugin_Stop;
}

public Action:Timer_RespawnPlayers( Handle:hTimer )
{
    return Plugin_Stop;
}

public Action:Timer_RespawnPlayers_Fix( Handle:hTimer )
{

    return Plugin_Stop;
}

public Action:Timer_UpdateEquipment( Handle:hTimer, any:iUserID )
{
    new client = GetClientOfUserId( iUserID );

    return Plugin_Stop;
}

public Action:Timer_GiveWeapon( Handle:hTimer, Handle:hPack )
{

    return Plugin_Stop;
}

public Action:Timer_UseWeapon( Handle:hTimer, Handle:hPack )
{
    return Plugin_Stop;
}

//TODO this belongs in OnGameFrame
public Action:Timer_UpdateHUD( Handle:hTimer, any:iUnused )
{
    return Plugin_Handled;
}

public Action:Timer_Announce( Handle:hTimer, any:iUserID )
{
    new client = GetClientOfUserId( iUserID );
    if( 0 < client <= MaxClients && IsClientInGame( client ) )
        PrintToChat( client, "\x07FF0000WARNING:\x07FFDA00 This is an unofficial game mode made by \x03XPenia Team\x07FFDA00." );
    return Plugin_Stop;
}

stock _ShowHudText( client, Handle:hHudSynchronizer = INVALID_HANDLE, const String:szFormat[], any:... )
{
    new String:szBuffer[250];
    VFormat( szBuffer, sizeof( szBuffer ), szFormat, 4 );

    if( ShowHudText( client, -1, szBuffer ) < 0 && hHudSynchronizer != INVALID_HANDLE )
    {
        ShowSyncHudText( client, hHudSynchronizer, szBuffer );
    }

}

stock UseWeapon( client, const String:szItem[] )
{
}

stock SetAmmo( client, iWeapon, iAmmo )
{
    if( 0 < client <= MaxClients && IsClientInGame( client ) )
    {
        new Handle:hPack;
        CreateDataTimer( 0.1, Timer_SetAmmo, hPack, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack, GetClientUserId( client ) );
        WritePackCell( hPack, EntIndexToEntRef( iWeapon ) );
        WritePackCell( hPack, iAmmo );
    }
}
public Action:Timer_SetAmmo( Handle:hTimer, Handle:hPack )
{
}

stock KillEdict( iEdict )
{
    if( iEdict > MaxClients && IsValidEdict( iEdict ) )
    {
        AcceptEntityInput( iEdict, "Kill" );
    }
}

stock StripWeapons( client )
{
}

stock ExtinguishClient( client )
{
    if( 0 < client <= MaxClients && IsClientInGame( client ) )
    {
        new entity = GetEntPropEnt( client, Prop_Data, "m_hEffectEntity" );
        if( entity > 0 && IsValidEdict( entity ) )
        {
            SetEntPropFloat( entity, Prop_Data, "m_flLifetime", 0.0 ); 
        }
    }
}

stock RestartTheGame()
{
    CreateTimer( 0.0, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE );

    PrintCenterTextAll("GUNGAME HAS BEEN RESTARTED!");
    PrintToChatAll("[GG] The game has been restarted!");
}

stock AllowMapEnd( bool:bState )
{
    if( fof_sv_dm_timer_ends_map != INVALID_HANDLE )
    {
        SetConVarBool( fof_sv_dm_timer_ends_map, bState, false, false );
    }
}

stock LeaderCheck( bool:bShowMessage = true )
{

    return;
}

stock bool:SetGameDescription( String:szNewValue[], bool:bOverride = true )
{
#if defined _SteamWorks_Included
    if( bOverride )
        return SteamWorks_SetGameDescription( szNewValue );

    new String:szOldValue[64];
    GetGameDescription( szOldValue, sizeof( szOldValue ), false );
    if( StrEqual( szOldValue, szNewValue ) )
    {
        GetGameDescription( szOldValue, sizeof( szOldValue ), true );
        return SteamWorks_SetGameDescription( szOldValue );
    }
#endif
    return false;
}




bool:IsGungameEnabled()
{
    return GetConVarBool(g_Cvar_Enabled);
}

bool:AreFistsEnabled()
{
    return GetConVarBool(g_Cvar_Fists);
}

bool:AreSuicidesAllowed()
{
    return GetConVarBool(g_Cvar_Suicides);
}

GetClientLevel(client)
{
    return g_ClientLevel[client];
}

RaiseClientLevel(client)
{
    if(g_ClientLevel < g_MaxLevel) g_ClientLevel[client] += 1;
}

LowerClientLevel(client)
{
    if(g_ClientLevel > BASE_LEVEL) g_ClientLevel[client] -= 1;
}

ResetClientLevel(client)
{
    g_ClientLevel[client] = BASE_LEVEL;
}

bool:ClientHasWon(client)
{
    return GetClientLevel(client) == g_MaxLevel;
}

StripInvalidWeapons(client, const String:target_weapon[], const String:alt_target_weapon[])
{
    decl String:class_name[MAX_WEAPON_NAME_SIZE], String:target_weapon2[MAX_WEAPON_NAME_SIZE], String:alt_target_weapon2[MAX_WEAPON_NAME_SIZE];
    new weapon_ent, strip_occured=false, has_target_weapon=false, has_alt_target_weapon=false;
    new offs = FindSendPropInfo("CBasePlayer","m_hMyWeapons");

    Format(target_weapon2, sizeof(target_weapon2), "%s2", target_weapon);
    //Format(alt_target_weapon2, sizeof(alt_target_weapon2), "%s2", alt_target_weapon);
    for(new i = 0; i <= 47; i++)
    {
        weapon_ent = GetEntDataEnt2(client,offs + (i * 4));
        if(weapon_ent == -1) continue;
        GetEdictClassname(weapon_ent, class_name, sizeof(class_name));

        if(StrEqual(class_name, target_weapon) || StrEqual(class_name, target_weapon2))
        {
            has_target_weapon = true;
        }

        /*
        if(StrEqual(class_name, alt_target_weapon) || StrEqual(class_name, alt_target_weapon2))
        {
            has_alt_target_weapon = true;
        }
        */

        //TODO add case for fists
        if(!(
            StrEqual(class_name, target_weapon) || StrEqual(class_name, target_weapon2) ||
            //StrEqual(class_name, alt_target_weapon) || StrEqual(class_name, alt_target_weapon2) ||
            (AreFistsEnabled() && StrEqual(class_name, "weapon_fists")) //Case for allowing fists
            ) )
        {
            strip_occured=true;
            RemovePlayerItem(client, weapon_ent);
            RemoveEdict(weapon_ent);
        }
    }

    if(strip_occured && !has_target_weapon)
    {
        ForceEquipWeapon(client, target_weapon);
    }

    //TODO equip alternate weapon

}

ForceEquipWeapon(client, const String:weapon[])
{
    new String:tmp[MAX_WEAPON_NAME_SIZE];

    GivePlayerItem(client, weapon);

    Format(tmp, sizeof(tmp), "use %s", weapon);
    ClientCommand(client, tmp);
}

PrintWeaponLevelLists(max_level, String:weapon_level_list[][], String:weapon_level_list_alt[][])
{
    for(new level = BASE_LEVEL; level <= max_level; level++)
    {
        PrintToServer( "weapon_level_list[%d]: \"%s\"; weapon_level_list_alt[%d]: \"%s\"",
                level,
                weapon_level_list[level],
                level,
                weapon_level_list_alt[level]);
    }

    PrintToServer( "max_level: %d", max_level );
}

PrintClientLevels()
{
    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client) || IsFakeClient(client))
            continue;

        PrintToServer("%5d %L",
                GetClientLevel(client),
                client);
    }

}
