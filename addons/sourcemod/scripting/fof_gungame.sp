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

#define CHAT_PREFIX         "\x04 GG \x07FFDA00 "
#define CONSOLE_PREFIX      "- GG: "

#define MAX_WEAPON_LEVELS   128

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
new Handle:mp_bonusroundtime = INVALID_HANDLE;

new Float:flBonusRoundTime = 5.0;

//TODO clean this up; there are way too many globals
new bool:g_IsLateLoaded = false;
new bool:g_IsDeathmatch = false;
new Handle:g_HUD_Leader = INVALID_HANDLE;
new Handle:g_HUD_Level = INVALID_HANDLE;
new Handle:g_Weapons = INVALID_HANDLE;
new iAmmoOffset = -1;
new iWinner = 0;
new String:szWinner[MAX_NAME_LENGTH];
new iLeader = 0;
new iMaxLevel = 1;
new fof_teamplay = INVALID_ENT_REFERENCE;

new iPlayerLevel[MAXPLAYERS+1];
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
new String:g_WeaponLevelList[MAX_WEAPON_LEVELS]  = {"weapon_fists_ghost"};
new String:g_WeaponLevelList2[MAX_WEAPON_LEVELS] = {""};

public Plugin:myinfo =
{
    name = PLUGIN_NAME,
    author = "Leonardo, Modified by CrimsonTautology",
    description = "Gun Game for Fistful of Frags",
    version = PLUGIN_VERSION,
    url = "https://github.com/CrimsonTautology/sm_gungame_fof"
};

public APLRes:AskPluginLoad2(Handle:myself, bool:late, String:error[], err_max)
{
    g_IsLateLoaded = late;
    return APLRes_Success;
}

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

    fof_sv_dm_timer_ends_map = FindConVar( "fof_sv_dm_timer_ends_map" );

    HookConVarChange( mp_bonusroundtime = FindConVar( "mp_bonusroundtime" ), OnConVarChanged );

    AutoExecConfig();


    HookEvent( "player_activate", Event_PlayerActivate );
    HookEvent( "player_spawn", Event_PlayerSpawn );
    HookEvent( "player_shoot", Event_PlayerShoot );
    //HookEvent( "player_death", Event_PlayerDeath_Pre, EventHookMode_Pre );
    HookEvent( "player_death", Event_PlayerDeath );

    RegAdminCmd( "fof_gungame_restart", Command_RestartRound, ADMFLAG_GENERIC );
    RegAdminCmd( "fof_gungame_reload_cfg", Command_ReloadConfigFile, ADMFLAG_CONFIG );

    AddCommandListener( Command_item_dm_end, "item_dm_end" );

    g_HUD_Leader = CreateHudSynchronizer();
    g_HUD_Level = CreateHudSynchronizer();

    iAmmoOffset = FindSendPropInfo( "CFoF_Player", "m_iAmmo" );

    g_Weapons = CreateKeyValues( "gungame_weapons" );

    //TODO I don't think checking if late loaded is needed
    if(g_IsLateLoaded)
    {
        for( new i = 1; i <= MaxClients; i++ )
            if( IsClientInGame( i ) )
            {
                SDKHook( i, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
                SDKHook( i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost );
            }

        RestartTheGame();
    }

    HookEntityOutput( "logic_auto", "OnMapSpawn", Output_OnMapSpawn );
}

public OnPluginEnd()
{
    AllowMapEnd( true );
    //SetGameDescription( "Gun Game", false );
}

public OnClientDisconnect_Post( iClient )
{
    //if( iWinner == iClient ) iWinner = 0;
    
    new timeleft;
    if( GetMapTimeLeft( timeleft ) && timeleft > 0 && iWinner <= 0 )
        LeaderCheck();
}

public OnMapStart()
{
    new Handle:mp_teamplay = FindConVar( "mp_teamplay" );
    new Handle:fof_sv_currentmode = FindConVar( "fof_sv_currentmode" );
    if( mp_teamplay != INVALID_HANDLE && fof_sv_currentmode != INVALID_HANDLE )
        g_IsDeathmatch = ( GetConVarInt( mp_teamplay ) == 0 && GetConVarInt( fof_sv_currentmode ) == 1 );
    else
        SetFailState( "Missing mp_teamplay or/and fof_sv_currentmode console variable" );
    
    fof_teamplay = INVALID_ENT_REFERENCE;
    
    iWinner = 0;
    szWinner[0] = '\0';
    iLeader = 0;
    iMaxLevel = 1;
    for( new i = 0; i < sizeof( iPlayerLevel ); i++ )
    {
        iPlayerLevel[i] = 1;
        flLastKill[i] = 0.0;
        flLastLevelUP[i] = 0.0;
        flLastUse[i] = 0.0;
        flStart[i] = 0.0;
        bWasInTheLead[i] = false;
        bInTheLead[i] = false;
    }
    
    PrecacheSound( SOUND_STINGER1, true );
    PrecacheSound( SOUND_STINGER2, true );
    PrecacheSound( SOUND_FIGHT, true );
    PrecacheSound( SOUND_HUMILIATION, true );
    PrecacheSound( SOUND_LOSTLEAD, true );
    PrecacheSound( SOUND_TAKENLEAD, true );
    PrecacheSound( SOUND_TIEDLEAD, true );
    
    CreateTimer( 1.0, Timer_UpdateHUD, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE );
}

public Output_OnMapSpawn( const String:szOutput[], iCaller, iActivator, Float:flDelay )
{
    new iCrate = INVALID_ENT_REFERENCE;
    while( ( iCrate = FindEntityByClassname( iCrate, "fof_crate*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iCrate, "Kill" );
}

public OnConfigsExecuted()
{
    //TODO why are you failing instead of just disabling!!!???
    if( !IsGungameEnabled() || !g_IsDeathmatch )
        SetFailState( "The plugin is disabled due to server configuration" );
    
    SetGameDescription( "Gun Game", true );
    
    AllowMapEnd( false );
    
    ScanConVars();

    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadConfigFile(file, iMaxLevel, g_Weapons);
}

stock ScanConVars()
{
    //TODO handle this better
    flBonusRoundTime = FloatMax( 0.0, GetConVarFloat( mp_bonusroundtime ) );
}

LoadConfigFile(String:file[], &max_level, &Handle:weapons)
{
    max_level = 1;
    
    new String:path[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, path, sizeof(path), "configs/%s", file);

    if(weapons != INVALID_HANDLE) CloseHandle(weapons);
    weapons = CreateKeyValues( "gungame_weapons" );

    if(!FileToKeyValues(weapons, path))
    {
        LogError("Could not read Gun Game config file \"%s\"", path);
        SetFailState("Could not read Gun Game config file \"%s\"", path);
        return;
    }

    new String:tmp[16], level, String:player_weapon[2][32];

    KvGotoFirstSubKey(weapons);

    do
    {
        KvGetSectionName(weapons, tmp, sizeof(tmp));

        //Skip non-level keys
        if(!IsCharNumeric(tmp[0]))
            continue;

        level = StringToInt(tmp);

        if(max_level < level) max_level = level;

        //TODO WHY ARE YOU NOT CACHING THIS?
        if(KvGotoFirstSubKey(weapons, false ))
        {
            KvGetSectionName(weapons, player_weapon[0], sizeof(player_weapon[]));
            KvGoBack(weapons);
            KvGetString(weapons, player_weapon[0], player_weapon[1], sizeof(player_weapon[]));
        }
        PrintToServer( "%sLevel %d = %s%s%s", CONSOLE_PREFIX, max_level, player_weapon[0], player_weapon[1][0] != '\0' ? ", " : "", player_weapon[1] );
    }
    while(KvGotoNextKey(weapons));
    PrintToServer( "%sTop level - %d", CONSOLE_PREFIX, max_level );
}

public OnConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] )
    ScanConVars();

public Action:Command_RestartRound( iClient, nArgs )
{
    RestartTheGame();
    return Plugin_Handled;
}

public Action:Command_ReloadConfigFile( iClient, nArgs )
{
    decl String:file[PLATFORM_MAX_PATH];
    GetConVarString(g_Cvar_Config, file, sizeof(file));
    LoadConfigFile(file, iMaxLevel, g_Weapons);

    return Plugin_Handled;
}

public Action:Command_item_dm_end( iClient, const String:szCommand[], nArgs )
{
    if( bFirstEquip[iClient] )
    {
        bFirstEquip[iClient] = false;
        CreateTimer( 0.0, Timer_UpdateEquipment, GetClientUserId( iClient ), TIMER_FLAG_NO_MAPCHANGE );
    }
    return Plugin_Continue;
}

public Event_PlayerActivate( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
    if( 0 < iClient <= MaxClients )
    {
        iPlayerLevel[ iClient ] = 1;
        flLastKill[ iClient ] = 0.0;
        flLastLevelUP[ iClient ] = 0.0;
        flLastUse[ iClient ] = 0.0;
        bFirstEquip[ iClient ] = true;
        bFirstSpawn[ iClient ] = true;
        flStart[ iClient ] = 0.0;
        if( IsClientInGame( iClient ) )
        {
            SDKHook( iClient, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
            SDKHook( iClient, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost );
        }
    }
}

public Event_PlayerSpawn( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iUserID = GetEventInt( hEvent, "userid" );
    new iClient = GetClientOfUserId( iUserID );
    
    if( 0 < iClient <= MaxClients && bFirstSpawn[iClient] )
    {
        bFirstSpawn[iClient] = false;
        flStart[iClient] = GetGameTime();
        CreateTimer( 2.0, Timer_Announce, iUserID, TIMER_FLAG_NO_MAPCHANGE );
    }
    
    CreateTimer( 0.1, Timer_UpdateEquipment, iUserID, TIMER_FLAG_NO_MAPCHANGE );
}

public Action:Event_PlayerDeath_Pre( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iVictim = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
    if( iWinner <= 0 && 0 < iVictim <= MaxClients && IsClientInGame( iVictim ) )
        StripWeapons( iVictim );
    return Plugin_Continue;
}

public Event_PlayerShoot( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iClient = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
    if( 0 <= iClient < sizeof( szLastWeaponFired ) )
        GetEventString( hEvent, "weapon", szLastWeaponFired[iClient], sizeof( szLastWeaponFired[] ) );
}

public Event_PlayerDeath( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iVictim = GetClientOfUserId( GetEventInt( hEvent, "userid" ) );
    new iKillerUID = GetEventInt( hEvent, "attacker" );
    new iKiller = GetClientOfUserId( iKillerUID );
    new iDmgBits = GetClientOfUserId( GetEventInt( hEvent, "damagebits" ) );
    
    if( iDmgBits & DMG_FALL )
        return;
    
    if( iWinner > 0 )
    {
        if( 0 < iVictim <= MaxClients && IsClientInGame( iVictim ) )
            EmitSoundToClient( iVictim, SOUND_HUMILIATION, .volume = 0.3 );
        return;
    }
    
    if( iVictim == iKiller || iKiller == 0 && GetEventInt( hEvent, "assist" ) <= 0 )
    {
        if( !AreSuicidesAllowed() && iPlayerLevel[iKiller] > 1 )
        {
            iPlayerLevel[iVictim]--;
            LeaderCheck();
            
            PrintCenterText( iVictim, "Ungraceful death! You are now level %d of %d.", iPlayerLevel[iVictim], iMaxLevel );
            PrintToChat( iVictim, "%sUngraceful death! You are now level %d of %d.", CHAT_PREFIX, iPlayerLevel[iVictim], iMaxLevel );
            EmitSoundToClient( iVictim,  SOUND_STINGER1);
        }
        return;
    }
    
    if( !( 0 < iKiller <= MaxClients && IsClientInGame( iVictim ) && IsClientInGame( iKiller ) ) )
        return;

    new Float:flCurTime = GetGameTime();
    if( ( flCurTime - flLastKill[iKiller] ) < 0.01 || ( flCurTime - flLastLevelUP[iKiller] ) <= 0.0 )
        return;
    flLastKill[iKiller] = flCurTime;
    
    new String:szWeapon[32];
    GetEventString( hEvent, "weapon", szWeapon, sizeof( szWeapon ) );
    if( StrEqual( szWeapon, "arrow" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_bow" );
    else if( StrEqual( szWeapon, "thrown_axe" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_axe" );
    else if( StrEqual( szWeapon, "thrown_knife" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_knife" );
    else if( StrEqual( szWeapon, "thrown_machete" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_machete" );
    else if( StrEqual( szWeapon, "blast" ) )
        strcopy( szWeapon, sizeof( szWeapon ), szLastWeaponFired[iKiller] );
    else
    {
        if( szWeapon[strlen(szWeapon)-1] == '2' )
            szWeapon[strlen(szWeapon)-1] = '\0';
        Format( szWeapon, sizeof( szWeapon ), "weapon_%s", szWeapon );
    }
    
    new String:szPlayerLevel[16];
    IntToString( iPlayerLevel[iKiller], szPlayerLevel, sizeof( szPlayerLevel ) );
    
    new String:szAllowedWeapon[2][24];
    KvRewind( g_Weapons );
    if( KvJumpToKey( g_Weapons, szPlayerLevel, false ) && KvGotoFirstSubKey( g_Weapons, false ) )
    {
        KvGetSectionName( g_Weapons, szAllowedWeapon[0], sizeof( szAllowedWeapon[] ) );
        KvGoBack( g_Weapons );
        KvGetString( g_Weapons, szAllowedWeapon[0], szAllowedWeapon[1], sizeof( szAllowedWeapon[] ) );
        KvGoBack( g_Weapons );
    }
    
    //PrintToConsole( iKiller, "%sKilled player with %s (required:%s%s%s)", CONSOLE_PREFIX, szWeapon, szAllowedWeapon[0], szAllowedWeapon[1][0] != '\0' ? "," : "", szAllowedWeapon[1] );
    
    if( szAllowedWeapon[0][0] == '\0' && szAllowedWeapon[1][0] == '\0' )
    {
        LogError( "Missing weapon for level %d!", iPlayerLevel[iKiller] );
        //return;
    }
    else if( !IsFakeClient( iKiller ) && !StrEqual( szWeapon, szAllowedWeapon[0] ) && !StrEqual( szWeapon, szAllowedWeapon[1] ) )
        return;
    
    flLastLevelUP[iKiller] = flCurTime;
    iPlayerLevel[iKiller]++;
    if( iPlayerLevel[iKiller] > iMaxLevel )
    {
        iPlayerLevel[iKiller] = iMaxLevel;
        iWinner = iKiller;
        GetClientName( iKiller, szWinner, sizeof( szWinner ) );
        
        new String:szTime[64], Float:flDiff = ( GetGameTime() - flStart[iKiller] );
        if( flDiff > 60.0 )
        {
            new iMins = 0;
            while( flDiff >= 60.0 )
            {
                flDiff -= 60.0;
                iMins++;
            }
            if( flDiff > 0.0 )
                FormatEx( szTime, sizeof( szTime ), "%d min. %.1f sec.", iMins, flDiff );
            else
                FormatEx( szTime, sizeof( szTime ), "%d min.", iMins );
        }
        else
            FormatEx( szTime, sizeof( szTime ), " %.1f sec.", flDiff );
        
        PrintCenterTextAll( "%N has won the round!", iKiller );
        PrintToChatAll( "%sPlayer \x03%N\x07FFDA00 has won the round in \x03%s", CHAT_PREFIX, iKiller, szTime );
        PrintToServer( "%sPlayer '%N' has won the round in %s", CONSOLE_PREFIX, iKiller, szTime );
        EmitSoundToAll(  SOUND_STINGER2);
        
        for( new i = 1; i <= MaxClients; i++ )
        {
            if( i != iKiller )
            {
                iPlayerLevel[i] = 1;
                flStart[i] = 0.0;
            }
            if( IsClientInGame( i ) )
                CreateTimer( 0.0, Timer_UpdateEquipment, GetClientUserId( i ), TIMER_FLAG_NO_MAPCHANGE );
        }
        
        CreateTimer( 3.0, Timer_RespawnAnnounce, .flags = TIMER_FLAG_NO_MAPCHANGE );
        AllowMapEnd( true );
    }
    else if( iPlayerLevel[iKiller] == iMaxLevel )
    {
        LeaderCheck( false );
        
        PrintCenterTextAll( "%N is on the final weapon!", iKiller );
        PrintToConsoleAll( "%sPlayer '%N' is on the final weapon!", CONSOLE_PREFIX, iKiller );
        EmitSoundToClient( iKiller,  SOUND_STINGER1);
    }
    else
    {
        LeaderCheck();
        
        PrintCenterText( iKiller, "Leveled up! You are now level %d of %d.", iPlayerLevel[iKiller], iMaxLevel );
        PrintToConsole( iKiller, "%sLeveled up! You are now level %d of %d.", CONSOLE_PREFIX, iPlayerLevel[iKiller], iMaxLevel );
        EmitSoundToClient( iKiller,  SOUND_STINGER1);
    }
    
    if( IsPlayerAlive( iKiller ) )
    {
        new heal = GetConVarInt(g_Cvar_Heal);

        if(heal > 0 )
        {
            SetEntityHealth(iKiller, GetClientHealth( iKiller ) + heal);
        }

        CreateTimer( 0.01, Timer_GetDrunk, iKillerUID, TIMER_FLAG_NO_MAPCHANGE );
    }
    
    CreateTimer( 0.0, Timer_UpdateEquipment, iKillerUID, TIMER_FLAG_NO_MAPCHANGE );
}
public Action:Timer_GetDrunk( Handle:hTimer, any:iUserID )
{
    new iClient = GetClientOfUserId( iUserID );
    new Float:drunkness = GetConVarFloat(g_Cvar_Drunkness);

    if(drunkness > 0.0 && 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
        SetEntPropFloat( iClient, Prop_Send, "m_flDrunkness", FloatMax( 0.0, GetEntPropFloat( iClient, Prop_Send, "m_flDrunkness" ) + drunkness));
    return Plugin_Stop;
}

public Action:Hook_OnTakeDamage( iVictim, &iAttacker, &iInflictor, &Float:flDamage, &iDmgType, &iWeapon, Float:vecDmgForce[3], Float:vecDmgPosition[3], iDmgCustom )
{
    if( 0 < iVictim <= MaxClients && IsClientInGame( iVictim ) )
    {
        //PrintToChat( iVictim, "cid#%d: dmgtype: %d, killer: %d (%d), dmg: %f, wpn: %d", iVictim, iDmgType, iAttacker, iInflictor, flDamage, iWeapon );
        
        if( iWinner > 0 && iWinner == iAttacker )
        {
            flDamage = 300.0;
            iDmgType |= DMG_CRUSH;
            return Plugin_Changed;
        }
        else if( /*iWinner == iVictim ||*/ ( iDmgType & (DMG_BURN|DMG_DIRECT) ) == (DMG_BURN|DMG_DIRECT) && iPlayerLevel[iVictim] >= iMaxLevel )
        {
            flDamage = 0.0;
            return Plugin_Changed;
        }
    }
    return Plugin_Continue;
}

public Hook_WeaponSwitchPost( iClient, iWeapon )
    if( iClient != iWinner && 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
    {
        new String:szPlayerLevel[16];
        IntToString( iPlayerLevel[iClient], szPlayerLevel, sizeof( szPlayerLevel ) );
        
        new String:szAllowedWeapon[2][24], Handle:hAllowedWeapons = CreateArray( 8 );
        if(AreFistsEnabled())
        {
            PushArrayString( hAllowedWeapons, "weapon_fists" );
        }
        if( iWinner <= 0 )
        {
            KvRewind( g_Weapons );
            if( KvJumpToKey( g_Weapons, szPlayerLevel, false ) && KvGotoFirstSubKey( g_Weapons, false ) )
            {
                KvGetSectionName( g_Weapons, szAllowedWeapon[0], sizeof( szAllowedWeapon[] ) );
                KvGoBack( g_Weapons );
                if( szAllowedWeapon[0][0] != '\0' )
                {
                    PushArrayString( hAllowedWeapons, szAllowedWeapon[0] );
                }
                
                KvGetString( g_Weapons, szAllowedWeapon[0], szAllowedWeapon[1], sizeof( szAllowedWeapon[] ) );
                KvGoBack( g_Weapons );
                if( szAllowedWeapon[1][0] != '\0' )
                {
                    PushArrayString( hAllowedWeapons, szAllowedWeapon[1] );
                }
            }
        }
        
        new iEntWeapon[2];
        iEntWeapon[0] = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon" );
        iEntWeapon[1] = GetEntPropEnt( iClient, Prop_Send, "m_hActiveWeapon2" );
        
        for( new String:szClassname[32], i, w = 0; w < sizeof( iEntWeapon ); w++ )
            if( iEntWeapon[w] > MaxClients && IsValidEdict( iEntWeapon[w] ) )
            {
                GetEntityClassname( iEntWeapon[w], szClassname, sizeof( szClassname ) );
                if( szClassname[strlen(szClassname)-1] == '2' )
                    szClassname[strlen(szClassname)-1] = '\0';
                if( StrContains( szClassname, "weapon_" ) != 0 )
                {
                    continue;
                }
                
                if( ( i = FindStringInArray( hAllowedWeapons, szClassname ) ) >= 0 )
                    RemoveFromArray( hAllowedWeapons, i );
                else
                {
                    RemovePlayerItem( iClient, iEntWeapon[w] );
                    KillEdict( iEntWeapon[w] );
                    
                    UseWeapon( iClient, "weapon_fists" );
                }
            }
        
        CloseHandle( hAllowedWeapons );
    }

public Action:Timer_RespawnAnnounce( Handle:hTimer, any:iUserID )
{
    CreateTimer( flBonusRoundTime, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE );
    CreateTimer( FloatMax( 0.0, ( flBonusRoundTime - 1.0 ) ), Timer_AllowMapEnd, .flags = TIMER_FLAG_NO_MAPCHANGE );
    if( flBonusRoundTime >= 1.0 )
        PrintToChatAll( "%sStarting new round in %d seconds...", CHAT_PREFIX, RoundToCeil( flBonusRoundTime ) );
    return Plugin_Stop;
}

public Action:Timer_AllowMapEnd( Handle:hTimer, any:iUserID )
{
    AllowMapEnd( true );
    return Plugin_Stop;
}

public Action:Timer_RespawnPlayers( Handle:hTimer )
{
    AllowMapEnd( true );
    
    iWinner = 0;
    szWinner[0] = '\0';
    iLeader = 0;
    for( new i = 0; i < sizeof( iPlayerLevel ); i++ )
    {
        iPlayerLevel[i] = 1;
        flLastKill[i] = 0.0;
        flStart[i] = 0.0;
        bWasInTheLead[i] = false;
        bInTheLead[i] = false;
        bWasInGame[i] = false;
        if( 0 < i <= MaxClients && IsClientInGame( i ) )
        {
            bUpdateEquipment[i] = true;
            bWasInGame[i] = GetClientTeam( i ) != 1;
            flStart[i] = GetGameTime();
        }
        ExtinguishClient( i );
    }
    
    CreateTimer( 0.05, Timer_RespawnPlayers_Fix, .flags = TIMER_FLAG_NO_MAPCHANGE );
    
    if( GetCommandFlags( "round_restart" ) != INVALID_FCVAR_FLAGS )
        ServerCommand( "round_restart" );
    else
    {
        if( IsValidEdict( fof_teamplay ) )
        {
            new String:szClassname[16];
            GetEntityClassname( fof_teamplay, szClassname, sizeof( szClassname ) );
            if( strcmp( szClassname, "fof_teamplay" ) )
                fof_teamplay = INVALID_ENT_REFERENCE;
        }
        else
            fof_teamplay = INVALID_ENT_REFERENCE;
        if( fof_teamplay == INVALID_ENT_REFERENCE && ( fof_teamplay = FindEntityByClassname( INVALID_ENT_REFERENCE, "fof_teamplay" ) ) == INVALID_ENT_REFERENCE )
            fof_teamplay = CreateEntityByName( "fof_teamplay" );
        if( fof_teamplay != INVALID_ENT_REFERENCE )
        {
            SetVariantInt( -1 );
            AcceptEntityInput( fof_teamplay, "InputRespawnPlayers" );
        }
    }
    
    new iEntity = INVALID_ENT_REFERENCE;
    while( ( iEntity = FindEntityByClassname( iEntity, "weapon_*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iEntity, "Kill" );
    iEntity = INVALID_ENT_REFERENCE;
    while( ( iEntity = FindEntityByClassname( iEntity, "dynamite*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iEntity, "Kill" );
    
    for( new iClient = 1; iClient <= MaxClients; iClient++ )
        if( IsClientInGame( iClient ) )
        {
            KillEdict( GetEntPropEnt( iClient, Prop_Send, "m_hRagdoll" ) );
            SetEntPropEnt( iClient, Prop_Send, "m_hRagdoll", INVALID_ENT_REFERENCE );
        }
    
    return Plugin_Stop;
}

public Action:Timer_RespawnPlayers_Fix( Handle:hTimer )
{
    AllowMapEnd( false );
    
    for( new i = 1; i <= MaxClients; i++ )
        if( IsClientInGame( i ) )
        {
            if( bWasInGame[i] && GetClientTeam( i ) == 1 )
                FakeClientCommand( i, "autojoin" );
            else if( bWasInGame[i] && !IsPlayerAlive( i ) )
                PrintToServer( "%sPlayer %L is still dead!", CONSOLE_PREFIX, i );
            else if( bUpdateEquipment[i] )
                Timer_UpdateEquipment( INVALID_HANDLE, GetClientUserId( i ) );
        }
    
    new timeleft;
    if( GetMapTimeLeft( timeleft ) && timeleft > 0 )
        EmitSoundToAll( SOUND_FIGHT, .volume = 0.3 );
    
    return Plugin_Stop;
}

public Action:Timer_UpdateEquipment( Handle:hTimer, any:iUserID )
{
    new iClient = GetClientOfUserId( iUserID );
    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;
    
    bUpdateEquipment[iClient] = false;
    
    if( iClient == iWinner || iWinner <= 0 && iPlayerLevel[iClient] >= iMaxLevel )
        IgniteEntity( iClient, 60.0 * 60.0 * 6.0, IsFakeClient( iClient ) );
    else
        ExtinguishClient( iClient );
    
    if( iWinner == iClient )
        SetEntityHealth( iClient, 500 );
    else
    {
        UseWeapon( iClient, "weapon_fists" );
        StripWeapons( iClient );
    }
    
    if( iWinner > 0 && iClient != iWinner )
    {
    }
    else
    {
        new String:szPlayerLevel[16];
        if( iWinner > 0 && iClient == iWinner )
            strcopy( szPlayerLevel, sizeof( szPlayerLevel ), "winner" );
        else
            IntToString( iPlayerLevel[iClient], szPlayerLevel, sizeof( szPlayerLevel ) );
        
        new String:szPlayerWeapon[2][32];
        KvRewind( g_Weapons );
        if( KvJumpToKey( g_Weapons, szPlayerLevel ) && KvGotoFirstSubKey( g_Weapons, false ) )
        {
            KvGetSectionName( g_Weapons, szPlayerWeapon[0], sizeof( szPlayerWeapon[] ) );
            KvGoBack( g_Weapons );
            KvGetString( g_Weapons, szPlayerWeapon[0], szPlayerWeapon[1], sizeof( szPlayerWeapon[] ) );
            KvGoBack( g_Weapons );
            if( StrEqual( szPlayerWeapon[0], szPlayerWeapon[1] ) )
                Format( szPlayerWeapon[1], sizeof( szPlayerWeapon[] ), "%s2", szPlayerWeapon[0] );
        }
        
        if( szPlayerWeapon[0][0] == '\0' && szPlayerWeapon[1][0] == '\0' )
        {
            if( iClient != iWinner )
            {
                LogError( "Missing weapon for level %d!", iPlayerLevel[iClient] );
            }
            return Plugin_Stop;
        }
        
        new Handle:hPack1;
        CreateDataTimer(0.10, Timer_GiveWeapon, hPack1, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack1, iUserID );
        WritePackString( hPack1, szPlayerWeapon[0] );
        
        new Handle:hPack2;
        CreateDataTimer(0.22, Timer_GiveWeapon, hPack2, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack2, iUserID );
        WritePackString( hPack2, szPlayerWeapon[1] );
    }
    
    return Plugin_Stop;
}

public Action:Timer_GiveWeapon( Handle:hTimer, Handle:hPack )
{
    ResetPack( hPack );
    
    new iUserID = ReadPackCell( hPack );
    new iClient = GetClientOfUserId( iUserID );
    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;
    
    new String:szWeapon[32];
    ReadPackString( hPack, szWeapon, sizeof( szWeapon ) );
    if( szWeapon[0] == '\0' )
        return Plugin_Stop;
    
    new iWeapon;
    if( ( iWeapon = GivePlayerItem( iClient, szWeapon ) ) > MaxClients )
    {
        if( StrContains( szWeapon, "weapon_dynamite" ) == 0 )
            SetAmmo( iClient, iWeapon, 100 );
        else if( StrEqual( szWeapon, "weapon_knife" ) )
            SetAmmo( iClient, iWeapon, 2 );
        else if( StrEqual( szWeapon, "weapon_axe" ) || StrEqual( szWeapon, "weapon_machete" ) )
            SetAmmo( iClient, iWeapon, 1 );
        
        new Handle:hPack1;
        CreateDataTimer( 0.1, Timer_UseWeapon, hPack1, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack1, iUserID );
        WritePackString( hPack1, szWeapon );
    }
    else
    {
        LogError( "Failed to generate %s", szWeapon );
    }
    
    return Plugin_Stop;
}

public Action:Timer_UseWeapon( Handle:hTimer, Handle:hPack )
{
    ResetPack( hPack );
    
    new iClient = GetClientOfUserId( ReadPackCell( hPack ) );
    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;
    
    new String:szWeapon[32];
    ReadPackString( hPack, szWeapon, sizeof( szWeapon ) );
    if( szWeapon[0] == '\0' )
        return Plugin_Stop;
    
    UseWeapon( iClient, szWeapon );
    return Plugin_Stop;
}

//TODO this belongs in OnGameFrame
public Action:Timer_UpdateHUD( Handle:hTimer, any:iUnused )
{
    new iTopLevel = 0, iClients[MaxClients+1], nClients = 0;
    if( iWinner <= 0 )
    {
        for( new i = 1; i <= MaxClients; i++ )
            if( IsClientInGame( i ) && iPlayerLevel[i] > iTopLevel )
                iTopLevel = iPlayerLevel[i];
        
        for( new i = 1; i <= MaxClients; i++ )
            if( IsClientInGame( i ) && iPlayerLevel[i] >= iTopLevel && GetClientTeam( i ) != 1 )
                iClients[nClients++] = i;
    }
    
    for( new i = 1; i <= MaxClients; i++ )
        if( IsClientInGame( i ) )
        {
            ClearSyncHud( i, g_HUD_Leader );
            ClearSyncHud( i, g_HUD_Level );
            
            if( iWinner > 0 )
            {
                if( nClients == iWinner )
                {
                    SetHudTextParams( 0.08, 0.08, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Leader, "YOU ARE THE WINNER" );
                }
                else
                {
                    SetHudTextParams( 0.08, 0.08, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Leader, "WINNER:" );
                    
                    SetHudTextParams( 0.08, 0.14, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Leader, "%s", szWinner );
                }
            }
            else if( nClients == 1 && iClients[0] == i && GetClientTeam( i ) != 1 )
            {
                SetHudTextParams( 0.08, 0.08, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                _ShowHudText( i, g_HUD_Leader, "THE LEADER" );
                
                if( iPlayerLevel[i] >= iMaxLevel )
                {
                    SetHudTextParams( 0.08, 0.14, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Level, "LEVEL: FINAL" );
                }
                else
                {
                    SetHudTextParams( 0.08, 0.14, 1.125, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Level, "LEVEL: %d", iPlayerLevel[i] );
                }
            }
            else
            {
                if( iTopLevel >= iMaxLevel )
                {
                    SetHudTextParams( 0.08, 0.08, 1.125, 220, 120, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Leader, "LEADER: FINAL LVL" );
                }
                else
                {
                    SetHudTextParams( 0.08, 0.08, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Leader, "LEADER: %d LVL", iTopLevel );
                }
                    
                if( GetClientTeam( i ) == 1 )
                    continue;
                
                if( iPlayerLevel[i] >= iMaxLevel )
                {
                    SetHudTextParams( 0.08, 0.14, 1.15, 0, 250, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Level, "YOU: FINAL LVL" );
                }
                else
                {
                    SetHudTextParams( 0.08, 0.14, 1.15, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, g_HUD_Level, "YOU: %d LVL", iPlayerLevel[i] );
                }
            }
        }
    return Plugin_Handled;
}

public Action:Timer_Announce( Handle:hTimer, any:iUserID )
{
    new iClient = GetClientOfUserId( iUserID );
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
        PrintToChat( iClient, "\x07FF0000WARNING:\x07FFDA00 This is an unofficial game mode made by \x03XPenia Team\x07FFDA00." );
    return Plugin_Stop;
}

stock _ShowHudText( iClient, Handle:hHudSynchronizer = INVALID_HANDLE, const String:szFormat[], any:... )
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
    {
        new String:szBuffer[250];
        VFormat( szBuffer, sizeof( szBuffer ), szFormat, 4 );
        
        if( ShowHudText( iClient, -1, szBuffer ) < 0 && hHudSynchronizer != INVALID_HANDLE )
        {
            ShowSyncHudText( iClient, hHudSynchronizer, szBuffer );
        }
        
    }

stock UseWeapon( iClient, const String:szItem[] )
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
    {
        if( IsPlayerAlive( iClient ) )
        {
            new Float:flCurTime = GetGameTime();
            if( ( flCurTime - flLastUse[iClient] ) >= 0.1 )
            {
                new bool:bFound = false;
                for( new iWeapon, String:szClassname[32], s = 0; s < 48; s++ )
                    if( IsValidEdict( ( iWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hMyWeapons", s ) ) ) )
                    {
                        GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );
                        //if( szClassname[strlen(szClassname)-1] == '2' )
                        //  szClassname[strlen(szClassname)-1] = '\0';
                        if( StrEqual( szClassname, szItem ) )
                        {
                            //EquipPlayerWeapon( iClient, iWeapon );
                            bFound = true;
                            break;
                        }
                    }
                if( bFound )
                {
                    FakeClientCommandEx( iClient, "use %s", szItem );
                    flLastUse[iClient] = flCurTime;
                }
            }
        }
    }

stock SetAmmo( iClient, iWeapon, iAmmo )
{
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
    {
        new Handle:hPack;
        CreateDataTimer( 0.1, Timer_SetAmmo, hPack, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack, GetClientUserId( iClient ) );
        WritePackCell( hPack, EntIndexToEntRef( iWeapon ) );
        WritePackCell( hPack, iAmmo );
    }
}
public Action:Timer_SetAmmo( Handle:hTimer, Handle:hPack )
{
    ResetPack( hPack );
    
    if( iAmmoOffset <= 0 )
        return Plugin_Stop;
    
    new iClient = GetClientOfUserId( ReadPackCell( hPack ) );
    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;
    
    new iWeapon = EntRefToEntIndex( ReadPackCell( hPack ) );
    if( iWeapon <= MaxClients || !IsValidEdict( iWeapon ) )
        return Plugin_Stop;
    
    SetEntData( iClient, iAmmoOffset + GetEntProp( iWeapon, Prop_Send, "m_iPrimaryAmmoType" ) * 4, ReadPackCell( hPack ) );
    return Plugin_Stop;
}

stock KillEdict( iEdict )
    if( iEdict > MaxClients && IsValidEdict( iEdict ) )
    {
        AcceptEntityInput( iEdict, "Kill" );
    }

stock StripWeapons( iClient )
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
    {
        for( new iWeapon, bool:bFound, iWeapons[48], String:szClassname[32], s = 0; s < 48; s++ )
        {
            bFound = false;
            szClassname[0] = '\0';
            if( IsValidEdict( ( iWeapon = GetEntPropEnt( iClient, Prop_Send, "m_hMyWeapons", s ) ) ) )
            {
                for( new w = 0; w < sizeof( iWeapons ); w++ )
                    if( iWeapons[w] == iWeapon )
                    {
                        bFound = true;
                    }
                if( bFound )
                    continue;
                for( new w = 0; w < sizeof( iWeapons ); w++ )
                    if( iWeapons[w] <= MaxClients )
                    {
                        iWeapons[w] = iWeapon;
                        break;
                    }
                GetEntityClassname( iWeapon, szClassname, sizeof( szClassname ) );
                if(AreFistsEnabled() && StrEqual( szClassname, "weapon_fists" ) )
                {
                    continue;
                }
                else
                {
                    RemovePlayerItem( iClient, iWeapon );
                    SetEntPropEnt( iClient, Prop_Send, "m_hMyWeapons", INVALID_ENT_REFERENCE, s );
                    KillEdict( iWeapon );
                }
            }
        }
    }

stock ExtinguishClient( iClient )
    if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
    {
        new iEntity = GetEntPropEnt( iClient, Prop_Data, "m_hEffectEntity" );
        if( iEntity > 0 && IsValidEdict( iEntity ) )
        {
            SetEntPropFloat( iEntity, Prop_Data, "m_flLifetime", 0.0 ); 
        }
    }

stock RestartTheGame()
{
    CreateTimer( 0.0, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE );
    
    PrintCenterTextAll( "GUNGAME HAS BEEN RESTARTED!" );
    PrintToChatAll( "%sThe game has been restarted!", CHAT_PREFIX );
}

stock AllowMapEnd( bool:bState )
    if( fof_sv_dm_timer_ends_map != INVALID_HANDLE )
        SetConVarBool( fof_sv_dm_timer_ends_map, bState, false, false );

stock LeaderCheck( bool:bShowMessage = true )
{
    new iTopLevel = 1, nLeaders = 0, iOldLeader = iLeader;
    
    for( new i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame( i ) )
        {
            bWasInTheLead[i] = bInTheLead[i];
            if( iPlayerLevel[i] > iTopLevel )
                iTopLevel = iPlayerLevel[i];
        }
        bInTheLead[i] = false;
    }
    
    for( new i = 1; i <= MaxClients; i++ )
        if( IsClientInGame( i ) && iPlayerLevel[i] >= iTopLevel && GetClientTeam( i ) != 1 )
        {
            bInTheLead[i] = true;
            iLeader = ( (++nLeaders) == 1 ? i : 0 );
        }
    
    for( new i = 1; i <= MaxClients; i++ )
        if( IsClientInGame( i ) )
        {
            if( bInTheLead[i] && ( !bWasInTheLead[i] || iOldLeader == i ) && nLeaders > 1 )
            {
                EmitSoundToClient( i, SOUND_TIEDLEAD, .volume = 0.3 );
                if( bShowMessage )
                    PrintToConsoleAll( "%s'%N' is also on the lead (level %d)", CONSOLE_PREFIX, i, iPlayerLevel[i] );
            }
            else if( bInTheLead[i] && iOldLeader != iLeader && iLeader == i )
            {
                EmitSoundToClient( i, SOUND_TAKENLEAD, .volume = 0.3 );
                if( bShowMessage )
                {
                    PrintCenterTextAll( "%N is on the lead", i, iPlayerLevel[i] );
                    PrintToConsoleAll( "%s'%N' is on the lead (level %d)", CONSOLE_PREFIX, i, iPlayerLevel[i] );
                }
            }
            else if( !bInTheLead[i] && bWasInTheLead[i] )
                EmitSoundToClient( i, SOUND_LOSTLEAD, .volume = 0.3 );
        }
    
    return nLeaders;
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


stock PrintToConsoleAll( const String:szFormat[], any:... )
    if( szFormat[0] != '\0' )
    {
        decl String:szBuffer[1024];
        VFormat( szBuffer, sizeof( szBuffer ), szFormat, 2 );
        
        PrintToServer( szBuffer );
        for( new i = 1; i <= MaxClients; i++ )
            if( IsClientInGame( i ) )
                PrintToConsole( i, szBuffer );
    }

stock Float:FloatMax( Float:flValue1, Float:flValue2 )
    return FloatCompare( flValue1, flValue2 ) >= 0 ? flValue1 : flValue2;


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
