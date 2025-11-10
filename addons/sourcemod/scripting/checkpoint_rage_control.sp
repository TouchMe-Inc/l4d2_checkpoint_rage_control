#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <left4dhooks>
#include <colors>

#define CALL_OPCODE 0xE8

#define L4D2Team_Survivor 2
#define L4D2Team_Infected 3
#define L4D2Infected_Tank 8

int g_iOriginalBytes[5];
int g_iModifiedBytes[5] = {
    0x31,
    0xC0,
    0x0f,
    0x1f,
    0x00
};

StringMap g_smTickdownMaps;
Address   g_pPatchTarget;
ConVar    g_cvAllMaps;

public Plugin myinfo = {
    name        = "Checkpoint Rage Control",
    author      = "ProdigySim, Visor",
    description = "Enable tank to lose rage while survivors are in saferoom",
    version     = "build_0003",
    url         = "https://github.com/Attano/L4D2-Competitive-Framework"
}

public void OnPluginStart()
{
    LoadTranslations("checkpoint_rage_control.phrases");

    InitGameData();

    g_cvAllMaps = CreateConVar(
        "crc_global", "1",
        "Remove saferoom frustration preservation mechanic on all maps by default",
        FCVAR_NONE, true, 0.0, true, 1.0
    );

    RegServerCmd("saferoom_frustration_tickdown", Cmd_SetSaferoomFrustrationTickdown);

    g_smTickdownMaps = new StringMap();
}

public void OnPluginEnd() {
    TogglePatch(false);
}

void InitGameData()
{
    GameData gmConf = new GameData("checkpoint_rage_control");
    if (!gmConf) SetFailState("Gamedata 'checkpoint_rage_control.txt' missing or corrupt");
    g_pPatchTarget = gmConf.GetAddress("SaferoomCheck_Sig");
    if (!g_pPatchTarget) SetFailState("Couldn't find the 'SaferoomCheck_Sig' address");
    int iOffset = gmConf.GetOffset("UpdateZombieFrustration_SaferoomCheck");
    g_pPatchTarget = g_pPatchTarget + (view_as<Address>(iOffset));
    if (LoadFromAddress(g_pPatchTarget, NumberType_Int8) != CALL_OPCODE)
        SetFailState("Saferoom Check Offset or signature seems incorrect");
    g_iOriginalBytes[0] = CALL_OPCODE;
    for (int i = 1; i < sizeof(g_iOriginalBytes); i++) {
        g_iOriginalBytes[i] = LoadFromAddress(g_pPatchTarget + view_as<Address>(i), NumberType_Int8);
    }
    delete gmConf;
}

Action Cmd_SetSaferoomFrustrationTickdown(int iArgs)
{
    char szMapName[64];
    GetCmdArg(1, szMapName, sizeof(szMapName));

    g_smTickdownMaps.SetValue(szMapName, true);

    return Plugin_Handled;
}

public void OnMapStart()
{
    if (g_cvAllMaps.BoolValue)
    {
        TogglePatch(true);
        return;
    }

    char szMapName[64];
    GetCurrentMap(szMapName, sizeof(szMapName));

    int iDummy;
    TogglePatch(g_smTickdownMaps.GetValue(szMapName, iDummy));
}

void Event_RoundStart(Event event, const char[] szEventName, bool bDontBroadcast) {
    ToggleEvents(false);
}

void Event_RoundEnd(Event event, const char[] szEventName, bool bDontBroadcast) {
    ToggleEvents(false);
}

void Event_EnteredStartArea(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));

    if (iClient <= 0 || !IsClientInGame(iClient)) {
        return;
    }

    if (GetClientTeam(iClient) != L4D2Team_Survivor) {
        return;
    }

    ToggleEvents(false);
    CPrintToChatAll("%t%t", "TAG", LosingFrustration() ? "LOSE_FRUSTRATION" : "KEEP_FRUSTRATION");
}

void Event_PlayerDeath(Event event, const char[] szEventName, bool bDontBroadcast)
{
    int iClient = GetClientOfUserId(event.GetInt("userid"));

    if (iClient <= 0 || !IsClientInGame(iClient) || !IsInfectedTank(iClient)) {
        return;
    }

    ToggleEvents(false);
}

public void L4D_OnSpawnTank_Post(int iClient, const float vPos[3], const float vAng[3]) {
    ToggleEvents(true);
}

bool LosingFrustration()
{
    if (g_cvAllMaps.BoolValue) {
        return true;
    }

    char szMapName[64];
    GetCurrentMap(szMapName, sizeof(szMapName));

    int iDummy;
    if (g_smTickdownMaps.GetValue(szMapName, iDummy)) {
        return true;
    }

    return false;
}

void ToggleEvents(bool bHook)
{
    static bool bHooked;
    if (!bHooked && bHook) {
        HookEvent("round_start",               Event_RoundStart);
        HookEvent("round_end",                 Event_RoundEnd);
        HookEvent("player_entered_start_area", Event_EnteredStartArea);
        HookEvent("player_death",              Event_PlayerDeath);
    } else if (bHooked && !bHook) {
        UnhookEvent("round_start",               Event_RoundStart);
        UnhookEvent("round_end",                 Event_RoundEnd);
        UnhookEvent("player_entered_start_area", Event_EnteredStartArea);
        UnhookEvent("player_death",              Event_PlayerDeath);
    }
    bHooked = bHook;
}

void TogglePatch(bool bPatch)
{
    static bool bIsPatched;
    if (!bIsPatched && bPatch) {
        for (int i = 0; i < sizeof(g_iModifiedBytes); i++) {
            StoreToAddress(g_pPatchTarget + view_as<Address>(i), g_iModifiedBytes[i], NumberType_Int8);
        }
    } else if (bIsPatched && !bPatch) {
        for (int i = 0; i < sizeof(g_iOriginalBytes); i++) {
            StoreToAddress(g_pPatchTarget + view_as<Address>(i), g_iOriginalBytes[i], NumberType_Int8);
        }
    }
    bIsPatched = bPatch;
}

/**
 * Is the player the tank?
 *
 * @param iClient client ID
 * @return bool
 */
bool IsInfectedTank(int iClient) {
    return (GetClientTeam(iClient) == L4D2Team_Infected && GetEntProp(iClient, Prop_Send, "m_zombieClass") == L4D2Infected_Tank);
}