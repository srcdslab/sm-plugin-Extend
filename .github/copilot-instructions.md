# SourceMod Extend Plugin - Copilot Instructions

## Repository Overview
This repository contains a SourcePawn plugin called "Extend" for SourceMod, a scripting platform for Source engine games. The plugin provides map extension tools including voting systems, admin commands for extending rounds/frags/wins/time, and integration with MapChooser Extended. This is a production game server plugin that must maintain high performance and stability.

## Technical Environment

### Language & Platform
- **Language**: SourcePawn (.sp files)
- **Platform**: SourceMod 1.11.0+ (uses modern SourceMod API)
- **Compiler**: SourcePawn compiler (spcomp) via SourceKnight build system
- **Target**: Source engine game servers (CS:GO, CS2, TF2, etc.)

### Build System
- **Primary Tool**: SourceKnight (Python-based SourceMod build system)
- **Configuration**: `sourceknight.yaml` defines dependencies and build targets
- **CI/CD**: GitHub Actions (`.github/workflows/ci.yml`) with automated building, testing, and releases
- **Dependencies**: 
  - SourceMod 1.11.0-git6917
  - MultiColors (for colored chat)
  - MapChooser Extended (optional integration)

### Key Files
- `addons/sourcemod/scripting/Extend.sp` - Main plugin source (492 lines)
- `addons/sourcemod/gamedata/Extend.games.txt` - Game signatures for memory operations
- `sourceknight.yaml` - Build configuration and dependencies
- `.github/workflows/ci.yml` - CI/CD pipeline

## SourcePawn Language Specifics

### Mandatory Pragmas
All .sp files MUST start with:
```sourcepawn
#pragma semicolon 1
#pragma newdecls required
```

### Variable Naming Conventions
- **Global variables**: Prefix with `g_` (e.g., `g_cvarExtendVote`)
- **Function names**: PascalCase (e.g., `HandleExtending`, `GenerateTimeleft`)
- **Local variables**: camelCase (e.g., `iRounds`, `sArgs`)
- **Constants**: ALL_CAPS with underscores (e.g., `VOTE_NO`, `VOTE_YES`)

### SourceMod API Usage
- Use `ConVar` instead of legacy cvar handles
- Use `CreateConVar()` for plugin-specific cvars with `AutoExecConfig(true)`
- Use `FindConVar()` for game cvars with null checks
- Always validate ConVar existence before registering related commands
- Use proper admin flags (e.g., `ADMFLAG_GENERIC`) for admin commands

### Memory Management
- Use `delete` for handles/objects without null checking (SourceMod handles this)
- Never use `.Clear()` for StringMap/ArrayList - creates memory leaks
- Instead: `delete objectName; objectName = new ArrayList();`
- Use `CloseHandle()` for GameConfig handles after use

### Include Files & Dependencies
```sourcepawn
#include <sourcemod>
#include <sdktools>
#include <multicolors>

#undef REQUIRE_PLUGIN
#tryinclude <mapchooser_extended>  // Optional dependency
#define REQUIRE_PLUGIN
```

## Code Style Guidelines

### Indentation & Formatting
- Use tabs (4 spaces equivalent)
- No trailing spaces
- Proper bracket placement following existing style
- Space around operators: `==`, `!=`, `=`, etc.

### Error Handling
- Always check ConVar existence before use
- Validate function parameters and user input
- Use `LogError()` for critical failures, `LogMessage()` for info
- Graceful degradation when optional features fail

### Chat Messages
- Use MultiColors for colored output: `CReplyToCommand()`, `CShowActivity2()`
- Follow format: `{green}[SM] {default}message {olive}highlighted`
- Use translation files for user-facing messages when possible

### Performance Best Practices
- Cache frequently accessed ConVar values
- Minimize operations in timer callbacks and frequent events
- Use efficient data structures (StringMap over arrays for lookups)
- Avoid string operations in hot code paths
- Consider server tick rate impact

## Project Structure & Conventions

### Plugin Information Block
```sourcepawn
public Plugin myinfo =
{
    name        = "Map extend tools",
    author      = "Obus + BotoX + .Rushaway", 
    description = "Adds map extension commands.",
    version     = "1.3.2",
    url         = ""
};
```

### Initialization Pattern
```sourcepawn
public void OnPluginStart()
{
    LoadTranslations("common.phrases");
    LoadTranslations("basevotes.phrases");
    
    // Find game ConVars with validation
    g_cvarMpTimeLimit = FindConVar("mp_timelimit");
    if (g_cvarMpTimeLimit != null)
    {
        // Register related commands
    }
    else
    {
        LogMessage("ConVar not found, disabling related functionality");
    }
    
    // Create plugin ConVars
    g_cvarExtendVote = CreateConVar("sm_extendvote_enabled", "1", "Description", FCVAR_NONE, true, 0.0, true, 1.0);
    
    AutoExecConfig(true);
}
```

### Command Registration Pattern
- Use descriptive command names with consistent prefixes (`sm_extend*`)
- Include helpful descriptions
- Set appropriate admin flags
- Validate argc before accessing arguments
- Provide usage messages for invalid input

## Testing & Validation

### Build Process
```bash
# Install SourceKnight if not available
pip install sourceknight

# Build the plugin
sourceknight build

# Output will be in .sourceknight/package/
```

### Manual Testing Checklist
1. **Compilation**: Plugin compiles without errors/warnings
2. **Loading**: Plugin loads without errors in SourceMod
3. **Commands**: All registered commands work as expected
4. **ConVars**: Plugin ConVars are created and functional
5. **Integration**: MapChooser Extended integration works when available
6. **Memory**: No memory leaks during normal operation
7. **Performance**: No significant impact on server tick rate

### Common Issues to Check
- ConVar existence validation
- Proper handle cleanup
- String buffer overflow protection
- Admin permission checks
- Translation key existence
- Game compatibility across Source engine versions

## Game-Specific Considerations

### Memory Operations
- GameConfig files define memory signatures for game engine access
- The plugin uses memory operations to cancel game over states
- Platform-specific addresses require gamedata validation
- Always check `GameConfGetAddress()` return values

### Source Engine Integration
- Understand mp_timelimit, mp_maxrounds, mp_fraglimit, mp_winlimit
- Handle negative values appropriately to prevent infinite games
- Work with game state changes (round end, map change events)
- Consider different game modes and their specific behaviors

### Server Performance
- This is a real-time game server plugin
- Avoid blocking operations
- Consider player count impact on operations
- Cache expensive calculations
- Use timers judiciously

## Common Patterns in This Codebase

### ConVar Value Extension
```sourcepawn
stock void ExtendMap(ConVar cvar, int value)
{
    if (cvar == g_cvarMpMaxRounds)
        g_cvarMpMaxRounds.IntValue += value;
    // etc.
    
    CancelGameOver(); // Reset game end state
}
```

### Argument Parsing with Negative Support
```sourcepawn
bool isNegative = (sArgs[0] == '-');
char sOutputArg[16];
GenerateArgs(sArgs, sizeof(sArgs), sOutputArg, isNegative);
if (!StringToIntEx(sOutputArg, iValue))
{
    // Handle invalid input
}
```

### Optional Feature Integration
```sourcepawn
#if defined _mapchooser_extended_included_
    if (GetFeatureStatus(FeatureType_Native, "GetExtendsLeft") == FeatureStatus_Available)
        return GetExtendsLeft();
#endif
```

## Debugging & Troubleshooting

### Logging Best Practices
- Use `LogAction()` for admin actions
- Use `LogError()` for failures
- Use `LogMessage()` for informational events
- Include relevant context (client info, values, etc.)

### Common Debugging Steps
1. Check SourceMod error logs
2. Verify gamedata signatures are current
3. Test ConVar availability on target game
4. Validate translation files exist
5. Check plugin load order dependencies

## Security Considerations

### Input Validation
- Always validate user input ranges
- Check for negative values where inappropriate
- Sanitize file paths and command arguments
- Validate admin permissions before executing privileged operations

### SQL Operations (If Added)
- All queries must be asynchronous
- Use parameterized queries to prevent SQL injection
- Properly escape user input
- Use transactions for multi-query operations
- Handle connection failures gracefully

## Version Management

- Follow semantic versioning in plugin info block
- Update version in `myinfo` structure
- Coordinate with repository tags
- Document breaking changes in commit messages
- Maintain backward compatibility when possible

## Contributing Guidelines

### Code Changes
- Maintain existing code style and conventions
- Test on multiple Source engine games when possible
- Verify performance impact on high-population servers
- Update documentation for new features
- Follow the existing error handling patterns

### Pull Request Checklist
- [ ] Plugin compiles without warnings
- [ ] No new memory leaks introduced
- [ ] Admin commands have proper permission checks
- [ ] New ConVars documented and have sensible defaults
- [ ] Translation support added for user messages
- [ ] Backward compatibility maintained
- [ ] Performance impact assessed

This plugin is actively used on production game servers, so stability, performance, and backward compatibility are critical considerations for any modifications.