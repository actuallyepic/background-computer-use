# Server Notifications Catalog

Every server-to-client notification this Codex binding can decode, grouped by wire-method prefix. Each entry links to the typed namespace member used with `CodexClient.notifications(of:)`.

## Topics

### account

- ``ServerNotifications/AccountLoginCompleted``
- ``ServerNotifications/AccountRateLimitsUpdated``
- ``ServerNotifications/AccountUpdated``

### app

- ``ServerNotifications/AppListUpdated``

### command

- ``ServerNotifications/CommandExecOutputDelta``

### Core

- ``ServerNotifications/ConfigWarning``
- ``ServerNotifications/DeprecationNotice``
- ``ServerNotifications/Error``

### fs

- ``ServerNotifications/FsChanged``

### fuzzyFileSearch

- ``ServerNotifications/FuzzyFileSearchSessionCompleted``
- ``ServerNotifications/FuzzyFileSearchSessionUpdated``

### hook

- ``ServerNotifications/HookCompleted``
- ``ServerNotifications/HookStarted``

### item

- ``ServerNotifications/ItemAgentMessageDelta``
- ``ServerNotifications/ItemAutoApprovalReviewCompleted``
- ``ServerNotifications/ItemAutoApprovalReviewStarted``
- ``ServerNotifications/ItemCommandExecutionOutputDelta``
- ``ServerNotifications/ItemCommandExecutionTerminalInteraction``
- ``ServerNotifications/ItemCompleted``
- ``ServerNotifications/ItemFileChangeOutputDelta``
- ``ServerNotifications/ItemMcpToolCallProgress``
- ``ServerNotifications/ItemPlanDelta``
- ``ServerNotifications/ItemReasoningSummaryPartAdded``
- ``ServerNotifications/ItemReasoningSummaryTextDelta``
- ``ServerNotifications/ItemReasoningTextDelta``
- ``ServerNotifications/ItemStarted``

### mcpServer

- ``ServerNotifications/McpServerOauthLoginCompleted``
- ``ServerNotifications/McpServerStartupStatusUpdated``

### model

- ``ServerNotifications/ModelRerouted``

### serverRequest

- ``ServerNotifications/ServerRequestResolved``

### skills

- ``ServerNotifications/SkillsChanged``

### thread

- ``ServerNotifications/ThreadArchived``
- ``ServerNotifications/ThreadClosed``
- ``ServerNotifications/ThreadCompacted``
- ``ServerNotifications/ThreadNameUpdated``
- ``ServerNotifications/ThreadRealtimeClosed``
- ``ServerNotifications/ThreadRealtimeError``
- ``ServerNotifications/ThreadRealtimeItemAdded``
- ``ServerNotifications/ThreadRealtimeOutputAudioDelta``
- ``ServerNotifications/ThreadRealtimeSdp``
- ``ServerNotifications/ThreadRealtimeStarted``
- ``ServerNotifications/ThreadRealtimeTranscriptDelta``
- ``ServerNotifications/ThreadRealtimeTranscriptDone``
- ``ServerNotifications/ThreadStarted``
- ``ServerNotifications/ThreadStatusChanged``
- ``ServerNotifications/ThreadTokenUsageUpdated``
- ``ServerNotifications/ThreadUnarchived``

### turn

- ``ServerNotifications/TurnCompleted``
- ``ServerNotifications/TurnDiffUpdated``
- ``ServerNotifications/TurnPlanUpdated``
- ``ServerNotifications/TurnStarted``

### windows

- ``ServerNotifications/WindowsWorldWritableWarning``

### windowsSandbox

- ``ServerNotifications/WindowsSandboxSetupCompleted``
