import Foundation
import AttentionControl
import AttentionMCPCore

// stdout 是本进程与 MCP 客户端之间唯一的协议通道，任何非协议输出都会破坏它。
// 这里先把 SIGPIPE 忽略掉：客户端提前关掉 stdout 时，写入不应该直接杀掉进程。
signal(SIGPIPE, SIG_IGN)

// 薄壳：协议处理在 AttentionMCPCore 里，控制通道在 AttentionControl 里，这里只负责接线。
let server = MCPServer(control: ControlClient())
StdioLoop(server: server).run()
