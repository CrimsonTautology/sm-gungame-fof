#pragma semicolon 1

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>
#undef REQUIRE_EXTENSIONS
#tryinclude <steamworks>

#define PLUGIN_VERSION		"1.3.1custom"
#define CHAT_PREFIX			"\x04 GG \x07FFDA00 "
#define CONSOLE_PREFIX		"- GG: "
//#define DEBUG				true

#if !defined IN_FOF_SWITCH
	#define IN_FOF_SWITCH	(1<<14)
#endif

#define SOUND_LEVELUP       "music/bounty/bounty_objective_stinger1.mp3"
#define SOUND_FINAL         "music/bounty/bounty_objective_stinger2.mp3"
#define SOUND_ROUNDWON      "music/round_end_stinger.mp3"
#define SOUND_HUMILIATION   "animals/chicken_pain1.wav"
#define SOUND_LOSTLEAD      "music/most_wanted_stinger.wav"
#define SOUND_TAKENLEAD     "halloween/ragged_powerup.wav"
#define SOUND_TIEDLEAD      "music/kill3.wav"

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

new Handle:sm_fof_gg_version = INVALID_HANDLE;
new Handle:fof_gungame_enabled = INVALID_HANDLE;
new Handle:fof_gungame_config = INVALID_HANDLE;
new Handle:fof_gungame_fists = INVALID_HANDLE;
new Handle:fof_gungame_equip_delay = INVALID_HANDLE;
new Handle:fof_gungame_heal = INVALID_HANDLE;
new Handle:fof_gungame_drunkness = INVALID_HANDLE;
new Handle:fof_gungame_suicides = INVALID_HANDLE;
new Handle:fof_gungame_logfile = INVALID_HANDLE;
new Handle:fof_sv_dm_timer_ends_map = INVALID_HANDLE;
new Handle:mp_bonusroundtime = INVALID_HANDLE;

new bool:bAllowFists = false;
new Float:flEquipDelay = 0.0;
new nHealAmount = 25;
new Float:flDrunkness = 2.5;
new bool:bSuicides = false;
new String:szLogFile[PLATFORM_MAX_PATH];
new Float:flBonusRoundTime = 5.0;

new bool:bLateLoaded = false;
new bool:bDeathmatch = false;
new Handle:hHUDSync1 = INVALID_HANDLE;
new Handle:hHUDSync2 = INVALID_HANDLE;
new Handle:hWeapons = INVALID_HANDLE;
new iAmmoOffset = -1;
new iWinner = 0;
new String:szWinner[MAX_NAME_LENGTH];
new iLeader = 0;
new iMaxLevel = 1;

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

new Handle:g_Timer_GiveWeapon1[MAXPLAYERS+1] = {INVALID_HANDLE, ...};
new Handle:g_Timer_GiveWeapon2[MAXPLAYERS+1] = {INVALID_HANDLE, ...};

public Plugin:myinfo =
{
	name = "[FoF] Gun Game",
	author = "Leonardo",
	description = "N/A",
	version = PLUGIN_VERSION,
	url = "http://www.xpenia.org/"
};

public APLRes:AskPluginLoad2( Handle:hPlugin, bool:bLateLoad, String:szError[], iErrorLength )
{
	bLateLoaded = bLateLoad;
	return APLRes_Success;
}

public OnPluginStart()
{
    sm_fof_gg_version = CreateConVar( "sm_fof_gg_version", PLUGIN_VERSION, "FoF Gun Game Plugin Version", FCVAR_PLUGIN|FCVAR_NOTIFY|FCVAR_REPLICATED|FCVAR_SPONLY|FCVAR_DONTRECORD );
    SetConVarString( sm_fof_gg_version, PLUGIN_VERSION );
    HookConVarChange( sm_fof_gg_version, OnVerConVarChanged );

    fof_gungame_enabled = CreateConVar( "fof_gungame_enabled", "0", _, FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0 );
    HookConVarChange( fof_gungame_config = CreateConVar( "fof_gungame_config", "gungame_weapons.txt", _, FCVAR_PLUGIN ), OnCfgConVarChanged );
    HookConVarChange( fof_gungame_fists = CreateConVar( "fof_gungame_fists", "1", "Allow or disallow fists.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0, true, 1.0 ), OnConVarChanged );
    HookConVarChange( fof_gungame_equip_delay = CreateConVar( "fof_gungame_equip_delay", "0.0", "Seconds before giving new equipment.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0 ), OnConVarChanged );
    HookConVarChange( fof_gungame_heal = CreateConVar( "fof_gungame_heal", "25", "Amount of health to restore on each kill.", FCVAR_PLUGIN|FCVAR_NOTIFY, true, 0.0 ), OnConVarChanged );
    HookConVarChange( fof_gungame_drunkness = CreateConVar( "fof_gungame_drunkness", "6.0", _, FCVAR_PLUGIN|FCVAR_NOTIFY ), OnConVarChanged );
    HookConVarChange( fof_gungame_suicides = CreateConVar( "fof_gungame_suicides", "1", "Set 0 to disallow suicides, level down for it.", FCVAR_PLUGIN|FCVAR_NOTIFY ), OnConVarChanged );
    HookConVarChange( fof_gungame_logfile = CreateConVar( "fof_gungame_logfile", "", _, FCVAR_PLUGIN ), OnConVarChanged );
    fof_sv_dm_timer_ends_map = FindConVar( "fof_sv_dm_timer_ends_map" );
    HookConVarChange( mp_bonusroundtime = FindConVar( "mp_bonusroundtime" ), OnConVarChanged );
    AutoExecConfig();

    HookEvent( "player_activate", Event_PlayerActivate );
    HookEvent( "player_spawn", Event_PlayerSpawn );
    HookEvent( "player_shoot", Event_PlayerShoot );
    HookEvent( "player_death", Event_PlayerDeath );
    HookEvent("round_start", Event_RoundStart);

    RegAdminCmd( "fof_gungame_restart", Command_RestartRound, ADMFLAG_GENERIC );
    RegAdminCmd( "fof_gungame_reload_cfg", Command_ReloadConfigFile, ADMFLAG_CONFIG );
    RegAdminCmd("fof_gungame_scores", Command_DumpScores, ADMFLAG_ROOT, "[DEBUG] List player score values");
    AddCommandListener( Command_item_dm_end, "item_dm_end" );

    hHUDSync1 = CreateHudSynchronizer();
    hHUDSync2 = CreateHudSynchronizer();

    iAmmoOffset = FindSendPropInfo( "CFoF_Player", "m_iAmmo" );

    hWeapons = CreateKeyValues( "gungame_weapons" );

    if( bLateLoaded )
    {
        for( new i = 1; i <= MaxClients; i++ )
            if( IsClientInGame( i ) )
            {
                SDKHook( i, SDKHook_OnTakeDamage, Hook_OnTakeDamage );
                SDKHook( i, SDKHook_WeaponSwitchPost, Hook_WeaponSwitchPost );
            }

        RestartTheGame();
    }
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

    iPlayerLevel[iClient] = 0;
}

public OnMapStart()
{
    new Handle:mp_teamplay = FindConVar( "mp_teamplay" );
    new Handle:fof_sv_currentmode = FindConVar( "fof_sv_currentmode" );
    if( mp_teamplay != INVALID_HANDLE && fof_sv_currentmode != INVALID_HANDLE )
        bDeathmatch = ( GetConVarInt( mp_teamplay ) == 0 && GetConVarInt( fof_sv_currentmode ) == 1 );
    else
        SetFailState( "Missing mp_teamplay or/and fof_sv_currentmode console variable" );

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

    PrecacheSound( SOUND_LEVELUP, true );
    PrecacheSound( SOUND_FINAL, true );
    PrecacheSound( SOUND_ROUNDWON, true );
    PrecacheSound( SOUND_HUMILIATION, true );
    PrecacheSound( SOUND_LOSTLEAD, true );
    PrecacheSound( SOUND_TAKENLEAD, true );
    PrecacheSound( SOUND_TIEDLEAD, true );
    for(new i=0; i < sizeof(g_RoundStartSounds); i++)
    {
        PrecacheSound(g_RoundStartSounds[i]);
    }

    CreateTimer( 1.0, Timer_UpdateHUD, .flags = TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE );
}

RemoveCrates()
{
    new ent = INVALID_ENT_REFERENCE;
    while( (ent = FindEntityByClassname(ent, "fof_crate*")) != INVALID_ENT_REFERENCE)
    {
		AcceptEntityInput(ent, "Kill" );
    }
}

public OnConfigsExecuted()
{
	if( !GetConVarBool( fof_gungame_enabled ) || !bDeathmatch )
		SetFailState( "The plugin is disabled due to server configuration" );
	
	SetGameDescription( "Gun Game", true );
	
	AllowMapEnd( false );
	
	ScanConVars();
	ReloadConfigFile();
}

stock ScanConVars()
{
	bAllowFists = GetConVarBool( fof_gungame_fists );
	flEquipDelay = FloatMax( 0.0, GetConVarFloat( fof_gungame_equip_delay ) );
	nHealAmount = Int32Max( 0, GetConVarInt( fof_gungame_heal ) );
	flDrunkness = GetConVarFloat( fof_gungame_drunkness );
	bSuicides = GetConVarBool( fof_gungame_suicides );
	GetConVarString( fof_gungame_logfile, szLogFile, sizeof( szLogFile ) );
	flBonusRoundTime = FloatMax( 0.0, GetConVarFloat( mp_bonusroundtime ) );
}

stock ReloadConfigFile()
{
	iMaxLevel = 1;
	
	new String:szConfigPath[PLATFORM_MAX_PATH], String:szNextLevel[16];
	GetConVarString( fof_gungame_config, szConfigPath, sizeof( szConfigPath ) );
	BuildPath( Path_SM, szConfigPath, sizeof( szConfigPath ), "configs/%s", szConfigPath );
	IntToString( iMaxLevel, szNextLevel, sizeof( szNextLevel ) );
	
	if( hWeapons != INVALID_HANDLE )
		CloseHandle( hWeapons );
	hWeapons = CreateKeyValues( "gungame_weapons" );
	if( FileToKeyValues( hWeapons, szConfigPath ) )
	{
		new String:szLevel[16], iLevel, String:szPlayerWeapon[2][32];
		if( KvGotoFirstSubKey( hWeapons ) )
			do
			{
				KvGetSectionName( hWeapons, szLevel, sizeof( szLevel ) );
				
				if( !IsCharNumeric( szLevel[0] ) )
					continue;
				
				iLevel = StringToInt( szLevel );
				if( iMaxLevel < iLevel )
					iMaxLevel = iLevel;
				
				if( KvGotoFirstSubKey( hWeapons, false ) )
				{
					KvGetSectionName( hWeapons, szPlayerWeapon[0], sizeof( szPlayerWeapon[] ) );
					KvGoBack( hWeapons );
					KvGetString( hWeapons, szPlayerWeapon[0], szPlayerWeapon[1], sizeof( szPlayerWeapon[] ) );
				}
				PrintToServer( "%sLevel %d = %s%s%s", CONSOLE_PREFIX, iMaxLevel, szPlayerWeapon[0], szPlayerWeapon[1][0] != '\0' ? ", " : "", szPlayerWeapon[1] );
			}
			while( KvGotoNextKey( hWeapons ) );
		PrintToServer( "%sTop level - %d", CONSOLE_PREFIX, iMaxLevel );
	}
	else
		PrintToServer( "%sFalied to parse the config file.", CONSOLE_PREFIX );
}

public OnConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] )
	ScanConVars();

public OnCfgConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] )
	ReloadConfigFile();

public OnVerConVarChanged( Handle:hConVar, const String:szOldValue[], const String:szNewValue[] )
	if( strcmp( szNewValue, PLUGIN_VERSION, false ) )
		SetConVarString( hConVar, PLUGIN_VERSION, true, true );

public Action:Command_RestartRound( iClient, nArgs )
{
	RestartTheGame();
	return Plugin_Handled;
}

public Action:Command_ReloadConfigFile( iClient, nArgs )
{
	ReloadConfigFile();
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

public Event_PlayerShoot( Handle:hEvent, const String:szEventName[], bool:bDontBroadcast )
{
    new iClient = GetClientOfUserId(GetEventInt(hEvent, "userid"));
    if(0 <= iClient < MaxClients)
    {
        GetEventString(hEvent, "weapon", szLastWeaponFired[iClient], sizeof(szLastWeaponFired[]));
    }
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
            EmitSoundToClient( iVictim, SOUND_HUMILIATION);
        return;
    }

    if( iVictim == iKiller || iKiller == 0 && GetEventInt( hEvent, "assist" ) <= 0 )
    {
        if( !bSuicides && iPlayerLevel[iKiller] > 1 )
        {
            iPlayerLevel[iVictim]--;
            LeaderCheck();

            PrintCenterText( iVictim, "Ungraceful death! You are now level %d of %d.", iPlayerLevel[iVictim], iMaxLevel );
            PrintToChat( iVictim, "%sUngraceful death! You are now level %d of %d.", CHAT_PREFIX, iPlayerLevel[iVictim], iMaxLevel );
            EmitSoundToClient( iVictim, SOUND_HUMILIATION );
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

    //Humiliate victim on fists kill by lowering their level
    if( (StrEqual(szWeapon, "fists") ||  StrEqual(szWeapon, "kick-fall") ) 
        && iPlayerLevel[iVictim] > 1 && 0 < iKiller <= MaxClients)
    {
        iPlayerLevel[iVictim]--;
        LeaderCheck();

        PrintCenterTextAll("%N was humiliated by %N and lost a level!", iVictim, iKiller);
        PrintToConsoleAll( "%N was humiliated by %N and lost a level!", iVictim, iKiller);
        PrintToChat( iVictim, "%sHumiliating death! You are now level %d of %d.", CHAT_PREFIX, iPlayerLevel[iVictim], iMaxLevel );
        EmitSoundToClient( iVictim, SOUND_HUMILIATION );
        EmitSoundToClient( iKiller, SOUND_HUMILIATION );
    }

    if( StrEqual( szWeapon, "arrow" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_bow" );
    else if( StrEqual( szWeapon, "thrown_axe" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_axe" );
    else if( StrEqual( szWeapon, "thrown_knife" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_knife" );
    else if( StrEqual( szWeapon, "thrown_machete" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_machete" );
    else if( StrEqual( szWeapon, "rpg_missile" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_rpg" );
    else if( StrEqual( szWeapon, "crossbow_bolt" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_crossbow" );
    else if( StrEqual( szWeapon, "grenade_ar2" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_ar2" );
    else if( StrEqual( szWeapon, "weapon_ar2" ) )
        strcopy( szWeapon, sizeof( szWeapon ), "weapon_ar2" );
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
    KvRewind( hWeapons );
    if( KvJumpToKey( hWeapons, szPlayerLevel, false ) && KvGotoFirstSubKey( hWeapons, false ) )
    {
        KvGetSectionName( hWeapons, szAllowedWeapon[0], sizeof( szAllowedWeapon[] ) );
        KvGoBack( hWeapons );
        KvGetString( hWeapons, szAllowedWeapon[0], szAllowedWeapon[1], sizeof( szAllowedWeapon[] ) );
        KvGoBack( hWeapons );
    }

    //PrintToConsole( iKiller, "%sKilled player with %s (required:%s%s%s)", CONSOLE_PREFIX, szWeapon, szAllowedWeapon[0], szAllowedWeapon[1][0] != '\0' ? "," : "", szAllowedWeapon[1] );

    if( szAllowedWeapon[0][0] == '\0' && szAllowedWeapon[1][0] == '\0' )
    {
        LogError( "Missing weapon for level %d!", iPlayerLevel[iKiller] );
        //return;
    }
    else if( !IsFakeClient( iKiller ) && !StrEqual( szWeapon, szAllowedWeapon[0] ) && !StrEqual( szWeapon, szAllowedWeapon[1] ) )
        return;

    flLastLevelUP[iKiller] = flCurTime + flEquipDelay;
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
        EmitSoundToAll( SOUND_ROUNDWON );

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
        EmitSoundToClient( iKiller, SOUND_FINAL );
    }
    else
    {
        LeaderCheck();

        PrintCenterText( iKiller, "Leveled up! You are now level %d of %d.", iPlayerLevel[iKiller], iMaxLevel );
        PrintToConsole( iKiller, "%sLeveled up! You are now level %d of %d.", CONSOLE_PREFIX, iPlayerLevel[iKiller], iMaxLevel );
        EmitSoundToClient( iKiller, SOUND_LEVELUP );
    }

    if( IsPlayerAlive( iKiller ) )
    {
        if( nHealAmount != 0 )
            SetEntityHealth( iKiller, GetClientHealth( iKiller ) + nHealAmount );
        CreateTimer( 0.01, Timer_GetDrunk, iKillerUID, TIMER_FLAG_NO_MAPCHANGE );
    }

    CreateTimer( 0.0, Timer_UpdateEquipment, iKillerUID, TIMER_FLAG_NO_MAPCHANGE );
}
public Action:Timer_GetDrunk( Handle:hTimer, any:iUserID )
{
    new iClient = GetClientOfUserId( iUserID );
    if( flDrunkness != 0.0 && 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
        SetEntPropFloat( iClient, Prop_Send, "m_flDrunkness", FloatMax( 0.0, GetEntPropFloat( iClient, Prop_Send, "m_flDrunkness" ) + flDrunkness ) );
    return Plugin_Stop;
}

public Event_RoundStart(Event:event, const String:name[], bool:dontBroadcast)
{
    RemoveCrates();

    //Clear scores
    iWinner = 0;
    szWinner[0] = '\0';
    iLeader = 0;
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
    }
    return Plugin_Continue;
}

public Hook_WeaponSwitchPost( iClient, iWeapon )
{
    if( iClient != iWinner && 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
    {
        WriteLog( "Hook_WeaponSwitchPost(%d): %L", iClient, iClient );

        new String:szPlayerLevel[16];
        IntToString( iPlayerLevel[iClient], szPlayerLevel, sizeof( szPlayerLevel ) );

        new String:szAllowedWeapon[2][24], Handle:hAllowedWeapons = CreateArray( 8 );
        if( bAllowFists )
        {
            WriteLog( "Hook_WeaponSwitchPost(%d): adding weapon_fists", iClient );
            PushArrayString( hAllowedWeapons, "weapon_fists" );
        }
        if( iWinner <= 0 )
        {
            KvRewind( hWeapons );
            if( KvJumpToKey( hWeapons, szPlayerLevel, false ) && KvGotoFirstSubKey( hWeapons, false ) )
            {
                KvGetSectionName( hWeapons, szAllowedWeapon[0], sizeof( szAllowedWeapon[] ) );
                KvGoBack( hWeapons );
                if( szAllowedWeapon[0][0] != '\0' )
                {
                    WriteLog( "Hook_WeaponSwitchPost(%d): adding '%s'", iClient, szAllowedWeapon[0] );
                    PushArrayString( hAllowedWeapons, szAllowedWeapon[0] );
                }

                KvGetString( hWeapons, szAllowedWeapon[0], szAllowedWeapon[1], sizeof( szAllowedWeapon[] ) );
                KvGoBack( hWeapons );
                if( szAllowedWeapon[1][0] != '\0' )
                {
                    WriteLog( "Hook_WeaponSwitchPost(%d): adding '%s'", iClient, szAllowedWeapon[1] );
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
                    WriteLog( "Hook_WeaponSwitchPost(%d): incorrect weapon '%s' (%s/%d)", iClient, szClassname, w == 0 ? "m_hActiveWeapon" : "m_hActiveWeapon2", iEntWeapon[w] );
                    continue;
                }

                if( ( i = FindStringInArray( hAllowedWeapons, szClassname ) ) >= 0 )
                    RemoveFromArray( hAllowedWeapons, i );
                else
                {
                    WriteLog( "Hook_WeaponSwitchPost(%d): unacceptable '%s' (%s/%d)", iClient, szClassname, w == 0 ? "m_hActiveWeapon" : "m_hActiveWeapon2", iEntWeapon[w] );

                    RemovePlayerItem( iClient, iEntWeapon[w] );
                    KillEdict( iEntWeapon[w] );

                    UseWeapon( iClient, "weapon_fists" );
                }
            }

        CloseHandle( hAllowedWeapons );
        WriteLog( "Hook_WeaponSwitchPost(%d): end", iClient );
    }
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
    }

    CreateTimer( 0.05, Timer_RespawnPlayers_Fix, .flags = TIMER_FLAG_NO_MAPCHANGE );

    if( GetCommandFlags( "round_restart" ) != INVALID_FCVAR_FLAGS )
        ServerCommand( "round_restart" );

    new iEntity = INVALID_ENT_REFERENCE;
    while( ( iEntity = FindEntityByClassname( iEntity, "weapon_*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iEntity, "Kill" );
    iEntity = INVALID_ENT_REFERENCE;
    while( ( iEntity = FindEntityByClassname( iEntity, "dynamite*" ) ) != INVALID_ENT_REFERENCE )
        AcceptEntityInput( iEntity, "Kill" );

    for( new iClient = 1; iClient <= MaxClients; iClient++ )
    {
        if( IsClientInGame( iClient ) )
        {
            KillEdict( GetEntPropEnt( iClient, Prop_Send, "m_hRagdoll" ) );
            SetEntPropEnt( iClient, Prop_Send, "m_hRagdoll", INVALID_ENT_REFERENCE );
        }
    }

    return Plugin_Stop;
}

public Action:Timer_RespawnPlayers_Fix( Handle:hTimer )
{
    AllowMapEnd( false );

    for( new i = 1; i <= MaxClients; i++ )
    {
        if( IsClientInGame( i ) )
        {
            if( bWasInGame[i] && GetClientTeam( i ) == 1 )
                FakeClientCommand( i, "autojoin" );
            else if( bWasInGame[i] && !IsPlayerAlive( i ) )
                PrintToServer( "%sPlayer %L is still dead!", CONSOLE_PREFIX, i );
            else if( bUpdateEquipment[i] )
                Timer_UpdateEquipment( INVALID_HANDLE, GetClientUserId( i ) );
        }
    }

    new timeleft;
    if( GetMapTimeLeft( timeleft ) && timeleft > 0 )
        EmitSoundToAll( g_RoundStartSounds[GetRandomInt(0, sizeof(g_RoundStartSounds) - 1)]);

    return Plugin_Stop;
}

public Action:Timer_UpdateEquipment( Handle:hTimer, any:iUserID )
{
    new iClient = GetClientOfUserId( iUserID );
    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;

    bUpdateEquipment[iClient] = false;

    if( iWinner == iClient )
        SetEntityHealth( iClient, 500 );
    else
    {
        UseWeapon( iClient, "weapon_fists" );
        StripWeapons( iClient );
    }

    if( iWinner > 0 && iClient != iWinner )
    {
        WriteLog( "Timer_GiveWeapon(%d): Updating the loadout. Level #%d, fists only (looser).", iClient, iPlayerLevel[iClient] );
    }
    else
    {
        new String:szPlayerLevel[16];
        if( iWinner > 0 && iClient == iWinner )
            strcopy( szPlayerLevel, sizeof( szPlayerLevel ), "winner" );
        else
            IntToString( iPlayerLevel[iClient], szPlayerLevel, sizeof( szPlayerLevel ) );

        new String:szPlayerWeapon[2][32];
        KvRewind( hWeapons );
        if( KvJumpToKey( hWeapons, szPlayerLevel ) && KvGotoFirstSubKey( hWeapons, false ) )
        {
            KvGetSectionName( hWeapons, szPlayerWeapon[0], sizeof( szPlayerWeapon[] ) );
            KvGoBack( hWeapons );
            KvGetString( hWeapons, szPlayerWeapon[0], szPlayerWeapon[1], sizeof( szPlayerWeapon[] ) );
            KvGoBack( hWeapons );
            if( StrEqual( szPlayerWeapon[0], szPlayerWeapon[1] ) )
                Format( szPlayerWeapon[1], sizeof( szPlayerWeapon[] ), "%s2", szPlayerWeapon[0] );
        }

        if( szPlayerWeapon[0][0] == '\0' && szPlayerWeapon[1][0] == '\0' )
        {
            if( iClient != iWinner )
            {
                LogError( "Missing weapon for level %d!", iPlayerLevel[iClient] );
                WriteLog( "Timer_GiveWeapon(%d): Updating the loadout. Level #%d, fists only (missing loadout).", iClient, iPlayerLevel[iClient] );
            }
            return Plugin_Stop;
        }

        new Handle:hPack1;
        //if(g_Timer_GiveWeapon1[iClient] != INVALID_HANDLE) CloseHandle(g_Timer_GiveWeapon1[iClient]);
        g_Timer_GiveWeapon1[iClient] = CreateDataTimer( flEquipDelay + 0.05, Timer_GiveWeapon, hPack1, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack1, iUserID );
        WritePackString( hPack1, szPlayerWeapon[0] );

        new Handle:hPack2;
        //if(g_Timer_GiveWeapon2[iClient] != INVALID_HANDLE) CloseHandle(g_Timer_GiveWeapon2[iClient]);
        g_Timer_GiveWeapon2[iClient] = CreateDataTimer( flEquipDelay + 0.18, Timer_GiveWeapon, hPack2, TIMER_FLAG_NO_MAPCHANGE|TIMER_DATA_HNDL_CLOSE );
        WritePackCell( hPack2, iUserID );
        WritePackString( hPack2, szPlayerWeapon[1] );

        WriteLog( "Timer_GiveWeapon(%d): Updating the loadout. Level #%d, weapon1: '%s', weapon2: '%s'%s.", iClient, iPlayerLevel[iClient], szPlayerWeapon[0], szPlayerWeapon[1], iClient == iWinner ? " (winner)" : "" );
    }

    return Plugin_Stop;
}

public Action:Timer_GiveWeapon( Handle:hTimer, Handle:hPack )
{
    ResetPack( hPack );

    new iUserID = ReadPackCell( hPack );
    new iClient = GetClientOfUserId( iUserID );

    //TODO FIXME
    //g_Timer_GiveWeapon1[iClient] = INVALID_HANDLE;
    //g_Timer_GiveWeapon2[iClient] = INVALID_HANDLE;

    if( !( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) ) )
        return Plugin_Stop;

    new String:szWeapon[32];
    ReadPackString( hPack, szWeapon, sizeof( szWeapon ) );
    if( szWeapon[0] == '\0' )
        return Plugin_Stop;

    WriteLog( "Timer_GiveWeapon(%d): %L", iClient, iClient );

    new iWeapon;
    if( ( iWeapon = GivePlayerItem( iClient, szWeapon ) ) > MaxClients )
    {
        WriteLog( "Timer_GiveWeapon(%d): generated %s/%d", iClient, szWeapon, iWeapon );

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
        WriteLog( "Timer_GiveWeapon(%d): failed to generate '%s'", iClient, szWeapon );
        LogError( "Failed to generate %s", szWeapon );
    }

    WriteLog( "Timer_GiveWeapon(%d): end", iClient );
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
            ClearSyncHud( i, hHUDSync1 );
            ClearSyncHud( i, hHUDSync2 );

            if( iWinner > 0 )
            {
                if( nClients == iWinner )
                {
                    SetHudTextParams( HUD1_X, HUD1_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync1, "YOU ARE THE WINNER" );
                }
                else
                {
                    SetHudTextParams( HUD1_X, HUD1_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync1, "WINNER:" );

                    SetHudTextParams( HUD2_X, HUD2_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync1, "%s", szWinner );
                }
            }
            else if( nClients == 1 && iClients[0] == i && GetClientTeam( i ) != 1 )
            {
                SetHudTextParams( HUD1_X, HUD1_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                _ShowHudText( i, hHUDSync1, "THE LEADER" );

                if( iPlayerLevel[i] >= iMaxLevel )
                {
                    SetHudTextParams( HUD2_X, HUD2_Y, 1.125, 0, 255, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync2, "LEVEL: FINAL" );
                }
                else
                {
                    SetHudTextParams( HUD2_X, HUD2_Y, 1.125, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync2, "LEVEL: %d", iPlayerLevel[i] );
                }
            }
            else
            {
                if( iTopLevel >= iMaxLevel )
                {
                    SetHudTextParams( HUD1_X, HUD1_Y, 1.125, 220, 120, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync1, "LEADER: FINAL LVL" );
                }
                else
                {
                    SetHudTextParams( HUD1_X, HUD1_Y, 1.125, 220, 220, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync1, "LEADER: %d LVL", iTopLevel );
                }

                if( GetClientTeam( i ) == 1 )
                    continue;

                if( iPlayerLevel[i] >= iMaxLevel )
                {
                    SetHudTextParams( HUD2_X, HUD2_Y, 1.15, 0, 250, 0, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync2, "YOU: FINAL LVL" );
                }
                else
                {
                    SetHudTextParams( HUD2_X, HUD2_Y, 1.15, 220, 220, 220, 180, 0, 0.0, 0.0, 0.0 );
                    _ShowHudText( i, hHUDSync2, "YOU: %d LVL", iPlayerLevel[i] );
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
    //WriteLog( "_ShowHudText(%d): %L", iClient, iClient );

    new String:szBuffer[250];
    VFormat( szBuffer, sizeof( szBuffer ), szFormat, 4 );

    if( ShowHudText( iClient, -1, szBuffer ) < 0 && hHudSynchronizer != INVALID_HANDLE )
    {
        //WriteLog( "_ShowHudText(%d): ShowSyncHudText( %d, %08X, '%s' )", iClient, iClient, hHudSynchronizer, szBuffer );
        ShowSyncHudText( iClient, hHudSynchronizer, szBuffer );
    }

    //WriteLog( "_ShowHudText(%d): end", iClient );
}

    stock UseWeapon( iClient, const String:szItem[] )
if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) )
{
    WriteLog( "UseWeapon(%d): %L", iClient, iClient );
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
                    //	szClassname[strlen(szClassname)-1] = '\0';
                    if( StrEqual( szClassname, szItem ) )
                    {
                        //EquipPlayerWeapon( iClient, iWeapon );
                        bFound = true;
                        break;
                    }
                }
            if( bFound )
            {
                WriteLog( "UseWeapon(%d): use %s", iClient, szItem );
                FakeClientCommandEx( iClient, "use %s", szItem );
                flLastUse[iClient] = flCurTime;
            }
        }
        else
            WriteLog( "UseWeapon(%d): %f < 0.1 (item:%s)", iClient, ( flCurTime - flLastUse[iClient] ), szItem );
    }
    else
        WriteLog( "UseWeapon(%d): client is dead (item:%s)", iClient, szItem );
    WriteLog( "UseWeapon(%d): end", iClient );
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
    WriteLog( "KillEdict: AcceptEntityInput( %d, \"Kill\" )", iEdict );
    AcceptEntityInput( iEdict, "Kill" );
}

    stock StripWeapons( iClient )
if( 0 < iClient <= MaxClients && IsClientInGame( iClient ) && IsPlayerAlive( iClient ) )
{
    WriteLog( "StripWeapons(%d): %L", iClient, iClient );
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
                    WriteLog( "StripWeapons(%d): found duplicate '%s' (slot:%d,entity:%d)", iClient, szClassname, s, iWeapon );
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
            if( bAllowFists && StrEqual( szClassname, "weapon_fists" ) )
            {
                WriteLog( "StripWeapons(%d): skipping '%s' (slot:%d,entity:%d)", iClient, szClassname, s, iWeapon );
                continue;
            }
            else
            {
                WriteLog( "StripWeapons(%d): removing '%s' (slot:%d,entity:%d)", iClient, szClassname, s, iWeapon );
                RemovePlayerItem( iClient, iWeapon );
                SetEntPropEnt( iClient, Prop_Send, "m_hMyWeapons", INVALID_ENT_REFERENCE, s );
                KillEdict( iWeapon );
            }
        }
    }
    WriteLog( "StripWeapons(%d): end", iClient );
}

stock RestartTheGame()
{
    CreateTimer( 0.0, Timer_RespawnPlayers, .flags = TIMER_FLAG_NO_MAPCHANGE );

    PrintCenterTextAll( "GUNGAME HAS BEEN RESTARTED!" );
    PrintToChatAll( "%sThe game has been restarted!", CHAT_PREFIX );
}

stock AllowMapEnd( bool:bState )
{
    if( fof_sv_dm_timer_ends_map != INVALID_HANDLE )
        SetConVarBool( fof_sv_dm_timer_ends_map, bState, false, false );
}

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
                EmitSoundToClient( i, SOUND_TIEDLEAD, .flags = SND_CHANGEPITCH, .pitch = 115);
                if( bShowMessage )
                    PrintToConsoleAll( "%s'%N' is also in the lead (level %d)", CONSOLE_PREFIX, i, iPlayerLevel[i] );
            }
            else if( bInTheLead[i] && iOldLeader != iLeader && iLeader == i )
            {
                EmitSoundToClient( i, SOUND_TAKENLEAD, .flags = SND_CHANGEPITCH, .pitch = 115);
                if( bShowMessage )
                {
                    PrintCenterTextAll( "%N is in the lead", i, iPlayerLevel[i] );
                    PrintToConsoleAll( "%s'%N' is in the lead (level %d)", CONSOLE_PREFIX, i, iPlayerLevel[i] );
                }
            }
            else if( !bInTheLead[i] && bWasInTheLead[i] )
                EmitSoundToClient( i, SOUND_LOSTLEAD);
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

stock WriteLog( const String:szFormat[], any:... )
{
#if defined DEBUG
    if( szLogFile[0] != '\0' && szFormat[0] != '\0' )
    {
        decl String:szBuffer[2048];
        VFormat( szBuffer, sizeof( szBuffer ), szFormat, 2 );
        LogToFileEx( szLogFile, "[%.3f] %s", GetGameTime(), szBuffer );
        //PrintToServer("[%.3f] %s", GetGameTime(), szBuffer );
    }
#endif
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

stock Int32Max( iValue1, iValue2 )
    return iValue1 > iValue2 ? iValue1 : iValue2;
stock Float:FloatMax( Float:flValue1, Float:flValue2 )
    return FloatCompare( flValue1, flValue2 ) >= 0 ? flValue1 : flValue2;

public Action:Command_DumpScores(caller, args)
{
    PrintToConsole(caller, "level notoriety frags deaths user");
    for (new client=1; client <= MaxClients; client++)
    {
        if(!IsClientInGame(client) || IsFakeClient(client))
            continue;

        PrintToConsole(caller, "%5d %9d %5d %6d %L %s",
                iPlayerLevel[client],
                GetEntProp(client, Prop_Send, "m_nLastRoundNotoriety"),
                GetEntProp(client, Prop_Data, "m_iFrags"),
                GetEntProp(client, Prop_Data, "m_iDeaths"),
                client,
                szLastWeaponFired[client]);
    }
    return Plugin_Handled;
}
