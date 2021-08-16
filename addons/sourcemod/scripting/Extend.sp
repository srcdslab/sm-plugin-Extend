#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

#define VOTE_NO "###no###"
#define VOTE_YES "###yes###"

ConVar g_cvarExtendVoteTime = null;
ConVar g_cvarExtendVotePercent = null;
ConVar g_cvarMpMaxRounds = null;
ConVar g_cvarMpFragLimit = null;
ConVar g_cvarMpWinLimit = null;
ConVar g_cvarMpTimeLimit = null;

bool g_bGameOver = false;
Address g_pGameOver;

public Plugin myinfo =
{
    name        = "Map extend tools",
    author      = "Obus + BotoX",
    description = "Adds map extension commands.",
    version     = "1.0",
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

	g_cvarExtendVoteTime = CreateConVar("sm_extendvote_time", "15", "Time that will be added to mp_timelimit shall the extend vote succeed", FCVAR_NONE, true, 1.0);
	g_cvarExtendVotePercent = CreateConVar("sm_extendvote_percent", "0.6", "Percentage of \"yes\" votes required to consider the vote successful", FCVAR_NONE, true, 0.05, true, 1.0);

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
	}
	else
	{
		LogMessage("Failed to find \"mp_timelimit\" console variable, related commands will be disabled.");
	}

	Handle hGameConf = LoadGameConfigFile("Extend.games");
	if(hGameConf == INVALID_HANDLE)
	{
		g_bGameOver = false;
		LogError("Couldn't load Extend.games game config! GameOver cancel disabled.");
		return;
	}

	if(!(g_pGameOver = GameConfGetAddress(hGameConf, "GameOver")))
	{
		g_bGameOver = false;
		CloseHandle(hGameConf);
		LogError("Couldn't get GameOver address from game config! GameOver cancel disabled.");
		return;
	}
	CloseHandle(hGameConf);

	g_bGameOver = true;
}

public Action Command_Extend_Rounds(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_extend_rounds <rounds>");
		return Plugin_Handled;
	}

	char sArgs[16];

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if (sArgs[0] == '-')
	{
		int iRoundsToDeduct;

		if (!StringToIntEx(sArgs[1], iRoundsToDeduct))
		{
			ReplyToCommand(client, "[SM] Invalid value");
			return Plugin_Handled;
		}

		g_cvarMpMaxRounds.IntValue -= iRoundsToDeduct;

		LogAction(client, -1, "\"%L\" deducted \"%d\" rounds from \"mp_maxrounds\"", client, iRoundsToDeduct);

		return Plugin_Handled;
	}

	int iRoundsToAdd;

	if (!StringToIntEx(sArgs, iRoundsToAdd))
	{
		ReplyToCommand(client, "[SM] Invalid value");
		return Plugin_Handled;
	}

	g_cvarMpMaxRounds.IntValue += iRoundsToAdd;
	CancelGameOver();

	LogAction(client, -1, "\"%L\" added \"%d\" rounds to \"mp_maxrounds\"", client, iRoundsToAdd);

	return Plugin_Handled;
}

public Action Command_Extend_Frags(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_extend_frags <frags>");
		return Plugin_Handled;
	}

	char sArgs[16];

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if (sArgs[0] == '-')
	{
		int iFragsToDeduct;

		if (!StringToIntEx(sArgs[1], iFragsToDeduct))
		{
			ReplyToCommand(client, "[SM] Invalid value");
			return Plugin_Handled;
		}

		g_cvarMpFragLimit.IntValue -= iFragsToDeduct;

		LogAction(client, -1, "\"%L\" deducted \"%d\" frags from \"mp_fraglimit\"", client, iFragsToDeduct);

		return Plugin_Handled;
	}

	int iFragsToAdd;

	if (!StringToIntEx(sArgs, iFragsToAdd))
	{
		ReplyToCommand(client, "[SM] Invalid value");
		return Plugin_Handled;
	}

	g_cvarMpFragLimit.IntValue += iFragsToAdd;
	CancelGameOver();

	LogAction(client, -1, "\"%L\" added \"%d\" frags to \"mp_fraglimit\"", client, iFragsToAdd);

	return Plugin_Handled;
}

public Action Command_Extend_Wins(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_extend_wins <wins>");
		return Plugin_Handled;
	}

	char sArgs[16];

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if (sArgs[0] == '-')
	{
		int iWinsToDeduct;

		if (!StringToIntEx(sArgs[1], iWinsToDeduct))
		{
			ReplyToCommand(client, "[SM] Invalid value");
			return Plugin_Handled;
		}

		g_cvarMpWinLimit.IntValue -= iWinsToDeduct;

		LogAction(client, -1, "\"%L\" deducted \"%d\" wins from \"mp_winlimit\"", client, iWinsToDeduct);

		return Plugin_Handled;
	}

	int iWinsToAdd;

	if (!StringToIntEx(sArgs, iWinsToAdd))
	{
		ReplyToCommand(client, "[SM] Invalid value");
		return Plugin_Handled;
	}

	g_cvarMpWinLimit.IntValue += iWinsToAdd;
	CancelGameOver();

	LogAction(client, -1, "\"%L\" added \"%d\" wins to \"mp_winlimit\"", client, iWinsToAdd);

	return Plugin_Handled;
}

public Action Command_Extend(int client, int argc)
{
	if (argc < 1)
	{
		ReplyToCommand(client, "[SM] Usage: sm_extend <time>");
		return Plugin_Handled;
	}

	char sArgs[16];

	GetCmdArg(1, sArgs, sizeof(sArgs));

	if (sArgs[0] == '-')
	{
		int iMinutesToDeduct;

		if (!StringToIntEx(sArgs[1], iMinutesToDeduct))
		{
			ReplyToCommand(client, "[SM] Invalid value");
			return Plugin_Handled;
		}

		g_cvarMpTimeLimit.IntValue -= iMinutesToDeduct;

		LogAction(client, -1, "\"%L\" deducted \"%d\" minutes from \"mp_timelimit\"", client, iMinutesToDeduct);

		return Plugin_Handled;
	}

	int iMinutesToAdd;

	if (!StringToIntEx(sArgs, iMinutesToAdd))
	{
		ReplyToCommand(client, "[SM] Invalid value");
		return Plugin_Handled;
	}

	g_cvarMpTimeLimit.IntValue += iMinutesToAdd;
	CancelGameOver();

	LogAction(client, -1, "\"%L\" added \"%d\" minutes to \"mp_timelimit\"", client, iMinutesToAdd);

	return Plugin_Handled;
}

int g_ExtendTime = 0;
public Action Command_ExtendVote(int client, int argc)
{
	if (IsVoteInProgress())
	{
		ReplyToCommand(client, "[SM] %t", "Vote in Progress");
		return Plugin_Handled;
	}

	g_ExtendTime = g_cvarExtendVoteTime.IntValue;
	if(argc == 1)
	{
		char sArg[64];
		GetCmdArg(1, sArg, sizeof(sArg));
		int Tmp = StringToInt(sArg);
		if(Tmp > 0)
			g_ExtendTime = Tmp > 30 ? 30 : Tmp;
	}

	Menu hVoteMenu = new Menu(Handler_VoteCallback, MenuAction_End|MenuAction_DisplayItem|MenuAction_VoteCancel|MenuAction_VoteEnd);
	hVoteMenu.SetTitle("Extend the current map (%d minutes)?", g_ExtendTime);

	hVoteMenu.AddItem(VOTE_YES, "Yes");
	hVoteMenu.AddItem(VOTE_NO, "No");

	hVoteMenu.OptionFlags = MENUFLAG_BUTTON_NOVOTE;
	hVoteMenu.ExitButton = false;
	hVoteMenu.DisplayVoteToAll(20);

	ShowActivity2(client, "[SM] ", "Initiated an extend vote");
	LogAction(client, -1, "\"%L\" initiated an extend vote.", client);

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

	 	if (strcmp(display, VOTE_NO) == 0 || strcmp(display, VOTE_YES) == 0)
	 	{
			char buffer[255];
			Format(buffer, sizeof(buffer), "%T", display, param1);

			return RedrawMenuItem(buffer);
		}
	}
	else if (action == MenuAction_VoteCancel && param1 == VoteCancel_NoVotes)
	{
		PrintToChatAll("[SM] %t", "No Votes Cast");
	}
	else if (action == MenuAction_VoteEnd)
	{
		char item[64], display[64];
		float percent, limit;
		int votes, totalVotes;

		GetMenuVoteInfo(param2, votes, totalVotes);
		menu.GetItem(param1, item, sizeof(item), _, display, sizeof(display));

		if (strcmp(item, VOTE_NO) == 0)
		{
			votes = totalVotes - votes;
		}

		limit = g_cvarExtendVotePercent.FloatValue;
		percent = float(votes) / float(totalVotes);

		if ((strcmp(item, VOTE_YES) == 0 && FloatCompare(percent, limit) < 0) || strcmp(item, VOTE_NO) == 0)
		{
			LogAction(-1, -1, "Extend vote failed.");
			PrintToChatAll("[SM] %t", "Vote Failed", RoundToNearest(100.0 * limit), RoundToNearest(100.0 * percent), totalVotes);
		}
		else
		{
			LogAction(-1, -1, "Extend vote successful, extending current map by \"%d\" minutes", g_ExtendTime);
			PrintToChatAll("[SM] %t", "Vote Successful", RoundToNearest(100.0 * percent), totalVotes);

			g_cvarMpTimeLimit.IntValue += g_ExtendTime;
			CancelGameOver();

			if (strcmp(item, VOTE_NO) == 0 || strcmp(item, VOTE_YES) == 0)
			{
				strcopy(item, sizeof(item), display);
			}
		}
	}

	return 0;
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
