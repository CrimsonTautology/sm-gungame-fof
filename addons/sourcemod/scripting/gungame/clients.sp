int g_PlayerLevels[MaxClients+1];
float g_PlayerStartTimes[MaxClients+1];

methodmap GGClient
{
    /** GGClient
      Represents a client in game that is in Gun Game
     */
    public GGClient(int client)
    {
        return view_as<GGClient>(client);
    }

    property int Index
    {
        public get() { return view_as<int>(this); }
    }

    property int Level
    {
        public get() { return g_PlayerLevels[this.Index]; }
    }

    property float Time
    {
        public get() { GetGameTime() - g_PlayerStartTimes[this.Index]; }
    }

    public void Clear()
    {
        g_PlayerLevels[this.Index] = 0;
        g_PlayerStartTimes[this.Index] = 0; 
    }

    public void Start()
    {
        g_PlayerLevels[this.Index] = 1;
        g_PlayerStartTimes[this.Index] = GetGameTime(); 
    }

    public void StripWeapons()
    {
        int weapon_ent;
        char class_name[MAX_KEY_LENGTH];
        int offs = FindSendPropInfo("CBasePlayer", "m_hMyWeapons");

        for(new i = 0; i <= 47; i++)
        {
            weapon_ent = GetEntDataEnt2(this.Index, offs + (i * 4));
            if(weapon_ent == -1) continue;

            GetEdictClassname(weapon_ent, class_name, sizeof(class_name));
            if(StrEqual(class_name, "weapon_fists")) continue;

            RemovePlayerItem(client, weapon_ent);
            RemoveEdict(weapon_ent);
        }
    }
}
