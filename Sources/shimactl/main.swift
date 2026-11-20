import Foundation

// shimactl: the CLI Claude Code hooks call.
// Stub: `shimactl event <name>` exits 0 immediately. The socket client comes later.
// Contract (design doc 2 / 4.2): always exit 0, even on bad arguments, so hooks never slow or break Claude Code.
exit(0)
