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
#define PLUGIN_TAG "{green}[Extend]"

// Largest mp_timelimit we allow; floats are exact up to 2^24 and the engine also converts it to int
#define MAX_TIMELIMIT_MINUTES 16777216.0

int g_iNumAttempts = 0;
int g_iExtendCount = 0;
int g_iExtendTime = 0;
float g_fVoteRequired = 0.0;

ConVar g_cvarExtendVoteTime;
ConVar g_cvarExtendVoteMaxDuration;
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

bool g_bCanCancelGameOver = false;
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
	LoadTranslations("extend.phrases");

	g_cvarMpMaxRounds = FindConVar("mp_maxrounds");
	g_cvarMpFragLimit = FindConVar("mp_fraglimit");
	g_cvarMpWinLimit = FindConVar("mp_winlimit");
	g_cvarMpTimeLimit = FindConVar("mp_timelimit");

	g_cvarExtendVote = CreateConVar("sm_extendvote_enabled", "1", "Enable Extend Vote? [1 = Enable | 0 = Disable]", FCVAR_NONE, true, 0.0, true, 1.0);
	g_cvarExtendVoteTime = CreateConVar("sm_extendvote_time", "15", "Time that will be added to mp_timelimit shall the extend vote succeed", FCVAR_NONE, true, 1.0);
	g_cvarExtendVoteMaxDuration = CreateConVar("sm_extendvote_max_duration", "30", "Maximum minutes an admin can request with \"sm_extend <time>\"", FCVAR_NONE, true, 1.0);
	g_cvarExtendVotePercent = CreateConVar("sm_extendvote_percent", "0.6", "Percentage of \"yes\" votes required to consider the vote successful", FCVAR_NONE, true, 0.05, true, 1.0);
	g_cvarExtendVotePercentIncrement = CreateConVar("sm_extendvote_percent_increment", "0.1", "Percentage added to the required \"yes\" votes for each successful extend vote on the current map", FCVAR_NONE, true, 0.0, true, 1.0);
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

		// Relies on the m_fRoundStartTime gamerules prop, which only Counter-Strike games have
		EngineVersion engine = GetEngineVersion();
		if (engine == Engine_CSS || engine == Engine_CSGO)
			RegAdminCmd("sm_roundextend", Command_RoundExtend, ADMFLAG_GENERIC, "sm_roundextend - Extend mp_timelimit elapsed time since the start of the round");
		else
			LogMessage("\"sm_roundextend\" is only supported on Counter-Strike games and will be disabled.");
	}
	else
		LogMessage("Failed to find \"mp_timelimit\" console variable, related commands will be disabled.");

	GameData hGameConf = new GameData("Extend.games");
	if (!hGameConf)
	{
		LogError("Couldn't load Extend.games game config! GameOver cancel disabled.");
		return;
	}

	g_pGameOver = hGameConf.GetAddress("GameOver");
	delete hGameConf;

	if (!g_pGameOver)
	{
		LogError("Couldn't get GameOver address from game config! GameOver cancel disabled.");
		return;
	}

	g_bCanCancelGameOver = true;
}

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max)
{
#if defined _mapchooser_extended_included_
	MarkNativeAsOptional("GetExtendsLeft");
#endif
	return APLRes_Success;
}

public void OnMapEnd()
{
	g_iNumAttempts = 0;
	g_iExtendCount = 0;
}

public Action Command_Extend_Rounds(int client, int argc)
{
	return HandleLimitCommand(client, argc, g_cvarMpMaxRounds, "sm_extend_rounds", "rounds");
}

public Action Command_Extend_Frags(int client, int argc)
{
	return HandleLimitCommand(client, argc, g_cvarMpFragLimit, "sm_extend_frags", "frags");
}

public Action Command_Extend_Wins(int client, int argc)
{
	return HandleLimitCommand(client, argc, g_cvarMpWinLimit, "sm_extend_wins", "wins");
}

public Action Command_Extend(int client, int argc)
{
	return HandleLimitCommand(client, argc, g_cvarMpTimeLimit, "sm_extendmap", "minutes");
}

public Action Command_ExtendVote(int client, int argc)
{
	if (!g_cvarExtendVote.BoolValue)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Feature Disabled");
		return Plugin_Handled;
	}

	if (g_cvarExtendVoteMaxFailedAttempt.IntValue > 0 && g_iNumAttempts >= g_cvarExtendVoteMaxFailedAttempt.IntValue)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Max Failed Votes", g_iNumAttempts);
		LogAction(-1, -1, "%L Attempting to start another extend vote after %d vote failed.. Clamped!", client, g_iNumAttempts);
		return Plugin_Handled;
	}

	// Check if all extends are required and if the client can bypass this requirement
	if (g_cvarRequireAllExtends.BoolValue && AreExtendsRemaining() && !CheckCommandAccess(client, "sm_extend_bypass", ADMFLAG_CHANGEMAP, false))
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Extends Remaining");
		return Plugin_Handled;
	}

	if (IsVoteInProgress())
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Vote in Progress");
		return Plugin_Handled;
	}

	g_iExtendTime = g_cvarExtendVoteTime.IntValue;
	if (argc == 1)
	{
		char sArg[16];
		GetCmdArg(1, sArg, sizeof(sArg));

		int Tmp;
		if (!ParseValue(sArg, Tmp) || Tmp < 0)
		{
			CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Invalid Value");
			return Plugin_Handled;
		}

		int maxDuration = g_cvarExtendVoteMaxDuration.IntValue;
		if (Tmp > 0)
			g_iExtendTime = Tmp > maxDuration ? maxDuration : Tmp;
	}

	if (!CanChangeLimit(client, g_cvarMpTimeLimit, g_iExtendTime))
		return Plugin_Handled;

	// Capture the requirement now so changing the convars mid-vote can't move it
	g_fVoteRequired = GetRequiredVoteRatio();

	Menu hVoteMenu = new Menu(Handler_VoteCallback, MenuAction_End|MenuAction_DisplayItem|MenuAction_VoteCancel|MenuAction_VoteEnd);
	char sRequired[16];
	FormatPercent(g_fVoteRequired, sRequired, sizeof(sRequired));
	hVoteMenu.SetTitle("Extend map by %d minutes? (%s%% required)", g_iExtendTime, sRequired);

	hVoteMenu.AddItem(VOTE_YES, "Yes");
	hVoteMenu.AddItem(VOTE_NO, "No");

	hVoteMenu.OptionFlags = MENUFLAG_BUTTON_NOVOTE;
	hVoteMenu.ExitButton = false;
	hVoteMenu.DisplayVoteToAll(20);

	char sTimeleft[128];
	int TimeLeft;
	GetMapTimeLeft(TimeLeft);
	if (TimeLeft >= 0)
		GenerateTimeleft(sTimeleft, sizeof(sTimeleft));
	else
		strcopy(sTimeleft, sizeof(sTimeleft), "0:00 (This is the last round!)");

	CShowActivity2(client, PLUGIN_TAG ... " ", "{default}%t", "Activity Vote Started");
	LogAction(client, -1, "\"%L\" Initiated an extend vote. (%d minutes)\nTimeLeft: %s", client, g_iExtendTime, sTimeleft);

	return Plugin_Handled;
}

public Action Command_RoundExtend(int client, int argc)
{
	float fElapsedTime = (GetGameTime() - GameRules_GetPropFloat("m_fRoundStartTime")) / 60.0;
	int elapsedMinutes = RoundToFloor(fElapsedTime);

	// Negative during freeze time, 0 in the first minute of the round
	if (elapsedMinutes <= 0)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Round Too Short");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, g_cvarMpTimeLimit, elapsedMinutes))
		return Plugin_Handled;

	ChangeLimit(g_cvarMpTimeLimit, elapsedMinutes);
	CPrintToChatAll("%s {default}%t", PLUGIN_TAG, "Round Extended", client, elapsedMinutes);
	LogAction(client, -1, "\"%L\" added \"%d\" minutes to \"mp_timelimit\" based on the current round time elapsed.", client, elapsedMinutes);

	return Plugin_Handled;
}

public int Handler_VoteCallback(Menu menu, MenuAction action, int param1, int param2)
{
	if (action == MenuAction_End)
		delete menu;
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
		CPrintToChatAll("%s {default}%t", PLUGIN_TAG, "No Votes Cast");
	}
	else if (action == MenuAction_VoteEnd)
	{
		char item[64];
		int votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		menu.GetItem(param1, item, sizeof(item));

		if (strcmp(item, VOTE_NO) == 0)
			votes = totalVotes - votes;

		// votes is now the yes count; the result depends only on it, not on which option won
		float fYesRatio = float(votes) / float(totalVotes);
		char sRequired[16], sYes[16];
		FormatPercent(g_fVoteRequired, sRequired, sizeof(sRequired));
		FormatPercent(fYesRatio, sYes, sizeof(sYes));

		// Small epsilon so sums like 0.6 + 0.05 * 2 (0.70000005) still accept exactly 70%
		if (fYesRatio + 0.0001 < g_fVoteRequired)
		{
			LogAction(-1, -1, "Extend vote failed. %s%% vote required. (Received %s%% of %d votes)", sRequired, sYes, totalVotes);
			PrintToServer("[SM] Vote failed. %s%% vote required. (Received %s%% of %d votes)", sRequired, sYes, totalVotes);
			CPrintToChatAll("%s {default}%t", PLUGIN_TAG, "Extend Vote Failed", sRequired, sYes, totalVotes);
			g_iNumAttempts++;
		}
		else
		{
			// The limit may have changed while the vote was running
			if (!CanChangeLimit(0, g_cvarMpTimeLimit, g_iExtendTime))
			{
				LogAction(-1, -1, "Extend vote passed, but \"mp_timelimit\" can no longer be extended. Extension skipped.");
				CPrintToChatAll("%s {default}%t", PLUGIN_TAG, "Extend Vote Passed No Limit");
				return 0;
			}

			char sOldTimeleft[128];
			GenerateTimeleft(sOldTimeleft, sizeof(sOldTimeleft));

			ChangeLimit(g_cvarMpTimeLimit, g_iExtendTime);

			char sTimeleft[128];
			GenerateTimeleft(sTimeleft, sizeof(sTimeleft));
			LogAction(-1, -1, "Extend vote successful. (Received %s%% of %d votes)\nExtending current map by \"%d\" minutes.\nPrevious TimeLeft: %s\nNew TimeLeft: %s", sYes, totalVotes, g_iExtendTime, sOldTimeleft, sTimeleft);
			PrintToServer("[SM] Vote successful. (Received %s%% of %d votes)", sYes, totalVotes);
			CPrintToChatAll("%s {default}%t", PLUGIN_TAG, "Extend Vote Successful", sYes, totalVotes);
			g_iNumAttempts = 0;
			g_iExtendCount++;
		}
	}

	return 0;
}

Action HandleLimitCommand(int client, int argc, ConVar cvar, const char[] sCommand, const char[] sUnit)
{
	if (argc < 1)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Command Usage", sCommand, sUnit);
		return Plugin_Handled;
	}

	char sArg[16];
	GetCmdArg(1, sArg, sizeof(sArg));

	int delta;
	if (!ParseValue(sArg, delta))
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Invalid Value");
		return Plugin_Handled;
	}

	if (!CanChangeLimit(client, cvar, delta))
		return Plugin_Handled;

	char sName[32];
	cvar.GetName(sName, sizeof(sName));

	bool isTime = (cvar == g_cvarMpTimeLimit);
	char sOldTimeleft[128];
	if (isTime)
		GenerateTimeleft(sOldTimeleft, sizeof(sOldTimeleft));

	ChangeLimit(cvar, delta);

	// Messages show the amount without its sign and say added or deducted instead
	bool isNegative = (delta < 0);
	int value = isNegative ? -delta : delta;

	char sAction[16], sPrep[8];
	strcopy(sAction, sizeof(sAction), isNegative ? "deducted" : "added");
	strcopy(sPrep, sizeof(sPrep), isNegative ? "from" : "to");

	CShowActivity2(client, PLUGIN_TAG ... " ", "{default}%t", isNegative ? "Activity Limit Deducted" : "Activity Limit Added", value, sUnit, sName);

	if (isTime)
	{
		char sTimeleft[128];
		GenerateTimeleft(sTimeleft, sizeof(sTimeleft));
		LogAction(client, -1, "\"%L\" %s \"%d\" %s %s \"%s\"\nPrevious Timeleft: %s\nNew Timeleft: %s", client, sAction, value, sUnit, sPrep, sName, sOldTimeleft, sTimeleft);
	}
	else
		LogAction(client, -1, "\"%L\" %s \"%d\" %s %s \"%s\"", client, sAction, value, sUnit, sPrep, sName);

	return Plugin_Handled;
}

stock float GetRequiredVoteRatio()
{
	float fBase = g_cvarExtendVotePercent.FloatValue;
	float limit = fBase + (g_cvarExtendVotePercentIncrement.FloatValue * float(g_iExtendCount));
	float fMax = g_cvarExtendVotePercentMax.FloatValue;

	// The cap only limits the increments, it never lowers the base requirement
	if (limit > fMax)
		limit = (fMax > fBase) ? fMax : fBase;

	return limit;
}

// Formats a 0-1 ratio as a percentage with one decimal, dropping a trailing ".0"
stock void FormatPercent(float ratio, char[] buffer, int size)
{
	FormatEx(buffer, size, "%.1f", 100.0 * ratio);

	int len = strlen(buffer);
	if (len > 2 && StrEqual(buffer[len - 2], ".0"))
		buffer[len - 2] = '\0';
}

stock void GenerateTimeleft(char[] sTimeleft, int size)
{
	int TimeLeft;
	if (!GetMapTimeLeft(TimeLeft) || TimeLeft < 0)
	{
		strcopy(sTimeleft, size, "N/A");
		return;
	}

	FormatEx(sTimeleft, size, "%02d:%02d", TimeLeft / 60, TimeLeft % 60);
}

// Parses "<n>" or "-<n>" into a signed amount
stock bool ParseValue(const char[] sArg, int &delta)
{
	bool isNegative = (sArg[0] == '-');
	int start = isNegative ? 1 : 0;

	if (sArg[start] == '\0')
		return false;

	// Accept plain digits only and build the number by hand, so nothing can wrap past cellmax
	int value = 0;
	for (int i = start; sArg[i] != '\0'; i++)
	{
		if (sArg[i] < '0' || sArg[i] > '9')
			return false;

		int digit = sArg[i] - '0';
		if (value > (cellmax - digit) / 10)
			return false;

		value = value * 10 + digit;
	}

	delta = isNegative ? -value : value;
	return true;
}

stock bool CanChangeLimit(int client, ConVar cvar, int delta)
{
	char sName[32];
	cvar.GetName(sName, sizeof(sName));

	// Read as a float for every limit, since mp_timelimit can be fractional
	bool isTime = (cvar == g_cvarMpTimeLimit);
	float fCurrent = cvar.FloatValue;

	// Adding to "no limit" would set a limit that may already be exceeded
	if (fCurrent <= 0.0)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Limit Not Set", sName);
		return false;
	}

	if (delta < 0 && fCurrent + float(delta) <= 0.0)
	{
		if (isTime)
			CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Time Limit Below Zero", sName, fCurrent + float(delta));
		else
			CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Limit Below Zero", sName, cvar.IntValue + delta);
		return false;
	}

	if (delta > 0 && isTime && fCurrent + float(delta) > MAX_TIMELIMIT_MINUTES)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Value Too Large", sName);
		return false;
	}

	if (delta > 0 && !isTime && delta > cellmax - cvar.IntValue)
	{
		CReplyToCommand(client, "%s {default}%t", PLUGIN_TAG, "Value Too Large", sName);
		return false;
	}

	return true;
}

// Adds a signed amount to a limit; mp_timelimit keeps fractional minutes
stock void ChangeLimit(ConVar cvar, int delta)
{
	if (cvar == g_cvarMpTimeLimit)
		cvar.FloatValue += float(delta);
	else
		cvar.IntValue += delta;

	if (delta >= 0)
		CancelGameOver();
}

void CancelGameOver()
{
	if (!g_bCanCancelGameOver)
		return;

	// Only undo game over when it actually happened, so normal extends don't reset movement
	if (LoadFromAddress(g_pGameOver, NumberType_Int8) == 0)
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
