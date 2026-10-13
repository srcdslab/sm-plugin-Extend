#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <mapchooser_extended>
#define REQUIRE_PLUGIN

#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"

int numAttempts = 0;
int g_iExtendCount = 0;

ConVar g_cvarExtendVoteTime;
ConVar g_cvarExtendVotePercent;
ConVar g_cvarExtendVotePercentIncrement;
ConVar g_cvarExtendVotePercentMax;
ConVar g_cvarExtendVoteMaxFailedAttempt;
ConVar g_cvarExtendVote;
ConVar g_cvarMpMaxRounds;
ConVar g_cvarMpFragLimit;
ConVar g_cvarMpWinLimit;
ConVar g_cvarMpTimeLimit;
ConVar g_cvarRequireAllExtends;

bool g_bGameOver = false;
Address g_pGameOver;

public Plugin myinfo =
{
	name        = "Map Extend Tools",
	author      = "Obus, BotoX, .Rushaway, koen",
	description = "Adds map extension commands.",
	version     = "1.4.0",
	url         = ""
};

public void OnPluginStart()
{
	LoadTranslations("common.phrases");
	LoadTranslations("basevotes.phrases");

	g_cvarMpMaxRounds = FindConVar("mp_maxrounds");
	g_cvarMpFragLimit = FindConVar("mp_fraglimit");
	g_cvarMpWinLimit = FindConVar("mp_winlimit");
	g_cvarMpTimeLimit = FindConVar("mp_timelimit");

	g_cvarExtendVote = CreateConVar("sm_extendvote_enabled", "1", "Enable Extend Vote? [1 = Enable | 0 = Disable]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarExtendVoteTime = CreateConVar("sm_extendvote_time", "15", "Time that will be added to mp_timelimit shall the extend vote succeed", FCVAR_NONE, true, 1.0);
	g_cvarExtendVotePercent = CreateConVar("sm_extendvote_percent", "0.6", "Percentage of \"yes\" votes required to consider the vote successful", FCVAR_NONE, true, 0.05, true, 1.0);
	g_cvarExtendVotePercentIncrement = CreateConVar("sm_extendvote_percent_increment", "0.0", "Percentage added to the required \"yes\" votes for each successful extend vote on the current map", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarExtendVotePercentMax = CreateConVar("sm_extendvote_percent_max", "0.9", "Maximum percentage of \"yes\" votes that can be required after increments", FCVAR_NONE, true, 0.05, true, 1.0);
	g_cvarExtendVoteMaxFailedAttempt = CreateConVar("sm_extendvote_maxfailed", "0", "Maximum Extend vote failed before locking the Extend vote command \n0 = Disable this function", FCVAR_NONE, true, 0.0);
	g_cvarRequireAllExtends = CreateConVar("sm_extendvote_require_all_extends", "1", "Require all mapchooser extends to be used before admins can call for extend? Only works with MapChooser Extended [1 = Yes | 0 = No]", FCVAR_NONE, true, 0.0, true, 1.0);

	AutoExecConfig(true);

	if (g_cvarMpMaxRounds != null)
		RegAdminCmd("sm_extend_rounds", Command_Extend_Rounds, ADMFLAG_GENERIC, "Add more rounds to mp_maxrounds");
	else
		LogMessage("Failed to find \"mp_maxrounds\" console variable, related commands will be disabled.");

	if (g_cvarMpFragLimit != null)
		RegAdminCmd("sm_extend_frags", Command_Extend_Frags, ADMFLAG_GENERIC, "Add more frags to mp_fraglimit");
	else
		LogMessage("Failed to find \"mp_fraglimit\" console variable, related commands will be disabled.");

	if (g_cvarMpWinLimit != null)
		RegAdminCmd("sm_extend_wins", Command_Extend_Wins, ADMFLAG_GENERIC, "Add more wins to mp_winlimit");
	else
		LogMessage("Failed to find \"mp_winlimit\" console variable, related commands will be disabled.");

	if (g_cvarMpTimeLimit != null)
	{
		RegAdminCmd("sm_extendmap", Command_Extend, ADMFLAG_GENERIC, "Add more time to mp_timelimit");
		RegAdminCmd("sm_extend", Command_ExtendVote, ADMFLAG_GENERIC, "sm_extend [time] - Start an extendvote");
		RegAdminCmd("sm_roundextend", Command_RoundExtend, ADMFLAG_GENERIC, "sm_roundextend - Extend mp_timelimit elapsed time since the start of the round");
	}
	else
		LogMessage("Failed to find \"mp_timelimit\" console variable, related commands will be disabled.");

	GameData hGameConf = new GameData("Extend.games");
	if (!hGameConf)
	{
		g_bGameOver = false;
		LogError("Couldn't load Extend.games game config! GameOver cancel disabled.");
		return;
	}

	if (!(g_pGameOver = hGameConf.GetAddress("GameOver")))
	{
		g_bGameOver = false;
		delete hGameConf;
		LogError("Couldn't get GameOver address from game config! GameOver cancel disabled.");
		return;
	}

	delete hGameConf;
	g_bGameOver = true;
}

public void OnMapEnd()
{
	numAttempts = 0;
	g_iExtendCount = 0;
}

public Action Command_Extend_Rounds(int client, int argc)
{
	if (argc < 1)
	{
		CReplyToCommand(client, "{green}[SM] {default}Usage: sm_extend_rounds {olive}<rounds>");
		return Plugin_Handled;
	}

	char sArgs[16];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int iRounds;
	bool isNegative = (sArgs[0] == '-');

	char sOutputArg[16];
	GenerateArgs(sArgs, sizeof(sArgs), sOutputArg, isNegative);
	if (!ParseValue(sOutputArg, iRounds))
	{
		CReplyToCommand(client, "{green}[SM] {default}Invalid value.");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, g_cvarMpMaxRounds, iRounds, isNegative))
		return Plugin_Handled;

	HandleExtending(g_cvarMpMaxRounds, iRounds, isNegative);
	CShowActivity2(client, "{green}[SM]{olive} ", "{default}%s %d rounds %s \"mp_maxrounds\"", isNegative ? "deducted" : "added", iRounds, isNegative ? "from" : "to");
	LogAction(client, -1, "\"%L\" %s \"%d\" rounds %s \"mp_maxrounds\"", client, isNegative ? "deducted" : "added", iRounds, isNegative ? "from" : "to");
	return Plugin_Handled;
}

public Action Command_Extend_Frags(int client, int argc)
{
	if (argc < 1)
	{
		CReplyToCommand(client, "{green}[SM] {default}Usage: sm_extend_frags {olive}<frags>");
		return Plugin_Handled;
	}

	char sArgs[16];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int iFrags;
	bool isNegative = (sArgs[0] == '-');

	char sOutputArg[16];
	GenerateArgs(sArgs, sizeof(sArgs), sOutputArg, isNegative);
	if (!ParseValue(sOutputArg, iFrags))
	{
		CReplyToCommand(client, "{green}[SM] {default}Invalid value.");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, g_cvarMpFragLimit, iFrags, isNegative))
		return Plugin_Handled;

	HandleExtending(g_cvarMpFragLimit, iFrags, isNegative);
	CShowActivity2(client, "{green}[SM]{olive} ", "{default}%s %d frags %s \"mp_fraglimit\"", isNegative ? "deducted" : "added", iFrags, isNegative ? "from" : "to");
	LogAction(client, -1, "\"%L\" %s \"%d\" frags %s \"mp_fraglimit\"", client, isNegative ? "deducted" : "added", iFrags, isNegative ? "from" : "to");

	return Plugin_Handled;
}

public Action Command_Extend_Wins(int client, int argc)
{
	if (argc < 1)
	{
		CReplyToCommand(client, "{green}[SM] {default}Usage: sm_extend_wins {olive}<wins>");
		return Plugin_Handled;
	}

	char sArgs[16];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int iWins;
	bool isNegative = (sArgs[0] == '-');

	char sOutputArg[16];
	GenerateArgs(sArgs, sizeof(sArgs), sOutputArg, isNegative);
	if (!ParseValue(sOutputArg, iWins))
	{
		CReplyToCommand(client, "{green}[SM] {default}Invalid value.");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, g_cvarMpWinLimit, iWins, isNegative))
		return Plugin_Handled;

	HandleExtending(g_cvarMpWinLimit, iWins, isNegative);
	CShowActivity2(client, "{green}[SM]{olive} ", "{default}%s %d wins %s \"mp_winlimit\"", isNegative ? "deducted" : "added", iWins, isNegative ? "from" : "to");
	LogAction(client, -1, "\"%L\" %s \"%d\" wins %s \"mp_winlimit\"", client, isNegative ? "deducted" : "added", iWins, isNegative ? "from" : "to");

	return Plugin_Handled;
}

public Action Command_Extend(int client, int argc)
{
	if (argc < 1)
	{
		CReplyToCommand(client, "{green}[SM] {default}Usage: sm_extendmap {olive}<time>");
		return Plugin_Handled;
	}

	char sArgs[16];
	GetCmdArg(1, sArgs, sizeof(sArgs));

	int iMinutes;
	bool isNegative = (sArgs[0] == '-');

	char sOutputArg[16];
	GenerateArgs(sArgs, sizeof(sArgs), sOutputArg, isNegative);
	if (!ParseValue(sOutputArg, iMinutes))
	{
		CReplyToCommand(client, "{green}[SM] {default}Invalid value.");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, g_cvarMpTimeLimit, iMinutes, isNegative))
		return Plugin_Handled;

	char sOldTimeleft[128];
	GenerateTimeleft(sOldTimeleft, sizeof(sOldTimeleft));
	HandleExtending(g_cvarMpTimeLimit, iMinutes, isNegative);

	char sTimeleft[128];
	GenerateTimeleft(sTimeleft, sizeof(sTimeleft));

	CShowActivity2(client, "{green}[SM]{olive} ", "{default}%s %d minutes %s \"mp_timelimit\"", isNegative ? "deducted" : "added", iMinutes, isNegative ? "from" : "to");
	LogAction(client, -1, "\"%L\" %s \"%d\" minutes %s \"mp_timelimit\"\nPrevious Timeleft: %s\nNew Timeleft: %s", client, isNegative ? "deducted" : "added", iMinutes, isNegative ? "from" : "to", sOldTimeleft, sTimeleft);
	return Plugin_Handled;
}

int g_ExtendTime = 0;
public Action Command_ExtendVote(int client, int argc)
{
	if (!g_cvarExtendVote.BoolValue)
	{
		CReplyToCommand(client, "{green}[SM] {default}This feature is currently disabled.");
		return Plugin_Handled;
	}
	
	if (g_cvarExtendVoteMaxFailedAttempt.IntValue > 0 && numAttempts >= g_cvarExtendVoteMaxFailedAttempt.IntValue)
	{
		CReplyToCommand(client, "{green}[SM] {default}Vote already failed %d time%s. Can't do more extend vote.", numAttempts, numAttempts > 1 ? "s" : "");
		LogAction(-1, -1, "%L Attempting to start another extend vote after %d vote failed.. Clamped!", client, numAttempts);
		return Plugin_Handled;
	}
	
	// Check if all extends are required and if the client can bypass this requirement
	if (g_cvarRequireAllExtends.BoolValue && AreExtendsRemaining() && !CheckCommandAccess(client, "sm_extend_bypass", ADMFLAG_CHANGEMAP, false))
	{
		CReplyToCommand(client, "{green}[SM] {default}Cannot start an extend vote until all mapchooser extends are used.");
		return Plugin_Handled;
	}

	if (IsVoteInProgress())
	{
		CReplyToCommand(client, "{green}[SM] {default}%t", "Vote in Progress");
		return Plugin_Handled;
	}

	g_ExtendTime = g_cvarExtendVoteTime.IntValue;
	if (argc == 1)
	{
		char sArg[64];
		GetCmdArg(1, sArg, sizeof(sArg));
		int Tmp = StringToInt(sArg);
		if (Tmp > 0)
			g_ExtendTime = Tmp > 30 ? 30 : Tmp;
	}

	if (!CanChangeLimit(client, g_cvarMpTimeLimit, g_ExtendTime, false))
		return Plugin_Handled;

	Menu hVoteMenu = new Menu(Handler_VoteCallback, MenuAction_End|MenuAction_DisplayItem|MenuAction_VoteCancel|MenuAction_VoteEnd);
	hVoteMenu.SetTitle("Extend the current map (%d minutes)? [%d%% required]", g_ExtendTime, GetRequiredVotePercent());

	hVoteMenu.AddItem(VOTE_YES, "Yes");
	hVoteMenu.AddItem(VOTE_NO, "No");

	hVoteMenu.OptionFlags = MENUFLAG_BUTTON_NOVOTE;
	hVoteMenu.ExitButton = false;
	hVoteMenu.DisplayVoteToAll(20);

	int TimeLeft;
	GetMapTimeLeft(TimeLeft);
	if (TimeLeft >= 0) 
	{
		char sTimeleft[128];
		GenerateTimeleft(sTimeleft, sizeof(sTimeleft));
		CShowActivity2(client, "{green}[SM]{olive} ", "{default}Initiated an extend vote.");
		LogAction(client, -1, "\"%L\" Initiated an extend vote. (%d minutes)\nTimeLeft: %s", client, g_ExtendTime, sTimeleft);
	}
	else
	{
		CShowActivity2(client, "{green}[SM]{olive} ", "{default}Initiated an extend vote.");
		LogAction(client, -1, "\"%L\" Initiated an extend vote. (%d minutes)\nTimeLeft: 0:00 (This is the last round!)", client, g_ExtendTime);
	}

	return Plugin_Handled;
}

public Action Command_RoundExtend(int client, int argc)
{
	ConVar cvarRoundTime = FindConVar("mp_roundtime");
	if (cvarRoundTime == null)
	{
		CReplyToCommand(client, "{green}[SM] {default}Failed to find \"mp_roundtime\" console variable.");
		return Plugin_Handled;
	}

	float fInitialRoundTime = cvarRoundTime.FloatValue;
	float fElapsedTime = (GameRules_GetPropFloat("m_fRoundStartTime") + GameRules_GetProp("m_iRoundTime") - GetGameTime()) / 60.0;
	int remainingTime = RoundToFloor(fInitialRoundTime - fElapsedTime);

	if (!CanChangeLimit(client, g_cvarMpTimeLimit, remainingTime, false))
		return Plugin_Handled;

	ExtendMap(g_cvarMpTimeLimit, remainingTime);
	CPrintToChatAll("{green}[SM]{default} %N added %d minutes to \"mp_timelimit\" based on the current round time elapsed.", client, remainingTime);
	LogAction(client, -1, "\"%L\" added \"%d\" minutes to \"mp_timelimit\" based on the current round time elapsed.", client, remainingTime);

	return Plugin_Handled;
}

public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
	{
		delete menu;
	}
	else if (action == MenuAction_DisplayItem)
	{
		char display[64];
		menu.GetItem(param2, "", 0, _, display, sizeof(display));

		if (strcmp(display, "No") == 0 || strcmp(display, "Yes") == 0)
		{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", display, param1);

			return RedrawMenuItem(buffer);
		}
	}
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		LogAction(-1, -1, "No Votes Cast. Extend Vote failed.");
		PrintToServer("[SM] %t", "No Votes Cast");
		CPrintToChatAll("{green}[SM] {default}%t", "No Votes Cast");
	}
	else if (action == MenuAction_VoteEnd)
	{
		char item[64];
		int votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		menu.GetItem(param1, item, sizeof(item));

		if (strcmp(item, VOTE_NO) == 0)
		{
			votes = totalVotes - votes;
		}

		int iTotalFailedPercent = GetRequiredVotePercent();
		int iTotalPercent = RoundToNearest(100.0 * float(votes) / float(totalVotes));

		// Compare in whole percents with integer math to avoid float rounding errors
		if ((strcmp(item, VOTE_YES) == 0 && votes * 100 < iTotalFailedPercent * totalVotes) || strcmp(item, VOTE_NO) == 0)
		{
			LogAction(-1, -1, "Extend %t", "Vote Failed", iTotalFailedPercent, iTotalPercent, totalVotes);
			PrintToServer("[SM] %t", "Vote Failed", iTotalFailedPercent, iTotalPercent, totalVotes);
			CPrintToChatAll("{green}[SM]{default} %t", "Vote Failed", iTotalFailedPercent, iTotalPercent, totalVotes);
			numAttempts++;
		}
		else
		{
			char sOldTimeleft[128];
			GenerateTimeleft(sOldTimeleft, sizeof(sOldTimeleft));

			ExtendMap(g_cvarMpTimeLimit, g_ExtendTime);

			char sTimeleft[128];
			GenerateTimeleft(sTimeleft, sizeof(sTimeleft));
			LogAction(-1, -1, "Extend %t \nExtending current map by \"%d\" minutes.\nPrevious TimeLeft: %s\nNew TimeLeft: %s","Vote Successful", iTotalPercent, totalVotes, g_ExtendTime, sOldTimeleft, sTimeleft);
			PrintToServer("[SM] %t", "Vote Successful", iTotalPercent, totalVotes);
			CPrintToChatAll("{green}[SM]{default} %t", "Vote Successful", iTotalPercent, totalVotes);
			numAttempts = 0;
			g_iExtendCount++;
		}
	}

	return 0;
}

stock void GenerateTimeleft(char[] sTimeleft, int size)
{
	int TimeLeft;
	if (!GetMapTimeLeft(TimeLeft) || TimeLeft < 0)
	{
		strcopy(sTimeleft, size, "N/A");
		return;
	}

	char sMinutes[5], sSeconds[5];
	FormatEx(sMinutes, sizeof(sMinutes), "%s%i", ((TimeLeft / 60) < 10) ? "0" : "", TimeLeft / 60);
	FormatEx(sSeconds, sizeof(sSeconds), "%s%i", ((TimeLeft % 60) < 10) ? "0" : "", TimeLeft % 60);
	FormatEx(sTimeleft, size, "%s:%s", sMinutes, sSeconds);
}

stock void GenerateArgs(char[] sArgToParse, int size, char[] sOutput, bool isNegative)
{
	if (isNegative)
		strcopy(sOutput, size, sArgToParse[1]);
	else
		strcopy(sOutput, size, sArgToParse);
}

stock bool ParseValue(const char[] sValue, int &value)
{
	// Require the whole string to be a non-negative number
	if (sValue[0] == '\0' || sValue[0] == '-')
		return false;

	if (StringToIntEx(sValue, value) != strlen(sValue))
		return false;

	return value >= 0;
}

stock bool CanChangeLimit(int client, ConVar cvar, int value, bool isNegative)
{
	char sName[32];
	cvar.GetName(sName, sizeof(sName));

	int current = cvar.IntValue;

	// Adding to "no limit" would set a limit that may already be exceeded
	if (current <= 0)
	{
		CReplyToCommand(client, "{green}[SM] {default}\"%s\" is 0 (no limit), there is nothing to change.", sName);
		return false;
	}

	if (isNegative && current - value <= 0)
	{
		CReplyToCommand(client, "{green}[SM] {default}\"%s\" (%d) can't be zero or negative.", sName, current - value);
		return false;
	}

	if (!isNegative && value > cellmax - current)
	{
		CReplyToCommand(client, "{green}[SM] {default}Value is too large for \"%s\".", sName);
		return false;
	}

	return true;
}

stock int GetRequiredVotePercent()
{
	float fBase = g_cvarExtendVotePercent.FloatValue;
	float limit = fBase + (g_cvarExtendVotePercentIncrement.FloatValue * float(g_iExtendCount));
	float fMax = g_cvarExtendVotePercentMax.FloatValue;

	// The cap only limits the increments, it never lowers the base requirement
	if (limit > fMax)
		limit = (fMax > fBase) ? fMax : fBase;

	return RoundToNearest(100.0 * limit);
}

stock void HandleExtending(ConVar cvar, int iRounds, bool isNegative)
{
	if (isNegative)
		ReduceMap(cvar, iRounds);
	else
		ExtendMap(cvar, iRounds);
}

stock void ExtendMap(ConVar cvar, int value)
{
	if (cvar == g_cvarMpMaxRounds)
		g_cvarMpMaxRounds.IntValue += value;
	else if (cvar == g_cvarMpFragLimit)
		g_cvarMpFragLimit.IntValue += value;
	else if (cvar ==g_cvarMpWinLimit)
		g_cvarMpWinLimit.IntValue += value;
	else if (cvar ==g_cvarMpTimeLimit)
		g_cvarMpTimeLimit.IntValue += value;

	CancelGameOver();
}

stock void ReduceMap(ConVar cvar, int value)
{
	if (cvar == g_cvarMpMaxRounds)
		g_cvarMpMaxRounds.IntValue -= value;
	else if (cvar == g_cvarMpFragLimit)
		g_cvarMpFragLimit.IntValue -= value;
	else if (cvar ==g_cvarMpWinLimit)
		g_cvarMpWinLimit.IntValue -= value;
	else if (cvar ==g_cvarMpTimeLimit)
		g_cvarMpTimeLimit.IntValue -= value;
}

void CancelGameOver()
{
	if (!g_bGameOver)
		return;

	StoreToAddress(g_pGameOver, 0, NumberType_Int8);

	for (int client = 1; client <= MaxClients; client++)
	{
		if (IsClientInGame(client))
		{
			if (IsClientObserver(client))
				SetEntityMoveType(client, MOVETYPE_NOCLIP);
			else
				SetEntityMoveType(client, MOVETYPE_WALK);
		}
	}
}

stock bool AreExtendsRemaining()
{
#if defined _mapchooser_extended_included_
	if (GetFeatureStatus(FeatureType_Native, "GetExtendsLeft") == FeatureStatus_Available)
		return GetExtendsLeft();
#endif

	// SourceMod's stock MapChooser has no way to read how many extends are left
	// (sm_mapvote_extend is the configured amount and never goes down), so don't block
	return false;
}
