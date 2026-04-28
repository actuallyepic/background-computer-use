# RPC Methods Catalog

Every client-to-server RPC method exposed by this Codex binding, grouped by wire-method prefix. Each entry links to the typed marker enum used with `CodexClient.call(_:params:)`.

## Topics

### account

- ``RPC/AccountLoginCancel``
- ``RPC/AccountLoginStart``
- ``RPC/AccountLogout``
- ``RPC/AccountRateLimitsRead``
- ``RPC/AccountRead``
- ``RPC/AccountSendAddCreditsNudgeEmail``

### app

- ``RPC/AppList``

### collaborationMode

- ``RPC/CollaborationModeList``

### command

- ``RPC/CommandExec``
- ``RPC/CommandExecResize``
- ``RPC/CommandExecTerminate``
- ``RPC/CommandExecWrite``

### config

- ``RPC/ConfigBatchWrite``
- ``RPC/ConfigMcpServerReload``
- ``RPC/ConfigRead``
- ``RPC/ConfigValueWrite``

### configRequirements

- ``RPC/ConfigRequirementsRead``

### Core

- ``RPC/FuzzyFileSearch``
- ``RPC/Initialize``

### device

- ``RPC/DeviceKeyCreate``
- ``RPC/DeviceKeyPublic``
- ``RPC/DeviceKeySign``

### experimentalFeature

- ``RPC/ExperimentalFeatureEnablementSet``
- ``RPC/ExperimentalFeatureList``

### externalAgentConfig

- ``RPC/ExternalAgentConfigDetect``
- ``RPC/ExternalAgentConfigImport``

### feedback

- ``RPC/FeedbackUpload``

### fs

- ``RPC/FsCopy``
- ``RPC/FsCreateDirectory``
- ``RPC/FsGetMetadata``
- ``RPC/FsReadDirectory``
- ``RPC/FsReadFile``
- ``RPC/FsRemove``
- ``RPC/FsUnwatch``
- ``RPC/FsWatch``
- ``RPC/FsWriteFile``

### fuzzyFileSearch

- ``RPC/FuzzyFileSearchSessionStart``
- ``RPC/FuzzyFileSearchSessionStop``
- ``RPC/FuzzyFileSearchSessionUpdate``

### marketplace

- ``RPC/MarketplaceAdd``
- ``RPC/MarketplaceRemove``
- ``RPC/MarketplaceUpgrade``

### mcpServer

- ``RPC/McpServerOauthLogin``
- ``RPC/McpServerResourceRead``
- ``RPC/McpServerToolCall``

### mcpServerStatus

- ``RPC/McpServerStatusList``

### memory

- ``RPC/MemoryReset``

### mock

- ``RPC/MockExperimentalMethod``

### model

- ``RPC/ModelList``

### plugin

- ``RPC/PluginInstall``
- ``RPC/PluginList``
- ``RPC/PluginRead``
- ``RPC/PluginUninstall``

### review

- ``RPC/ReviewStart``

### skills

- ``RPC/SkillsConfigWrite``
- ``RPC/SkillsList``

### thread

- ``RPC/ThreadApproveGuardianDeniedAction``
- ``RPC/ThreadArchive``
- ``RPC/ThreadBackgroundTerminalsClean``
- ``RPC/ThreadCompactStart``
- ``RPC/ThreadDecrementElicitation``
- ``RPC/ThreadFork``
- ``RPC/ThreadIncrementElicitation``
- ``RPC/ThreadInjectItems``
- ``RPC/ThreadList``
- ``RPC/ThreadLoadedList``
- ``RPC/ThreadMemoryModeSet``
- ``RPC/ThreadMetadataUpdate``
- ``RPC/ThreadNameSet``
- ``RPC/ThreadRead``
- ``RPC/ThreadRealtimeAppendAudio``
- ``RPC/ThreadRealtimeAppendText``
- ``RPC/ThreadRealtimeListVoices``
- ``RPC/ThreadRealtimeStart``
- ``RPC/ThreadRealtimeStop``
- ``RPC/ThreadResume``
- ``RPC/ThreadRollback``
- ``RPC/ThreadShellCommand``
- ``RPC/ThreadStart``
- ``RPC/ThreadTurnsList``
- ``RPC/ThreadUnarchive``
- ``RPC/ThreadUnsubscribe``

### turn

- ``RPC/TurnInterrupt``
- ``RPC/TurnStart``
- ``RPC/TurnSteer``

### windowsSandbox

- ``RPC/WindowsSandboxSetupStart``
