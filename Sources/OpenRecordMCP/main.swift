import MCP
import OpenRecordMCPServer

let server = await OpenRecordServer.make()
try await server.start(transport: StdioTransport())
await server.waitUntilCompleted()
