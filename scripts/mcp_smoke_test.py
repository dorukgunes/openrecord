#!/usr/bin/env python3
"""Talks MCP over stdio to openrecord-mcp and prints what each tool returns.

usage: scripts/mcp_smoke_test.py [path/to/openrecord-mcp] [--frames-dir DIR]
Set OPENRECORD_LIBRARY to point the server at a different recordings folder.
"""
import argparse
import base64
import json
import os
import subprocess
import sys

parser = argparse.ArgumentParser()
parser.add_argument("server", nargs="?", default="build/OpenRecord.app/Contents/MacOS/openrecord-mcp")
parser.add_argument("--frames-dir", help="save frames returned by get_frames here")
args = parser.parse_args()

proc = subprocess.Popen([args.server], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True, env=os.environ)
next_id = 0


def request(method, params=None):
    global next_id
    next_id += 1
    proc.stdin.write(json.dumps({"jsonrpc": "2.0", "id": next_id, "method": method, "params": params or {}}) + "\n")
    proc.stdin.flush()
    while True:
        message = json.loads(proc.stdout.readline())
        if message.get("id") == next_id:
            if "error" in message:
                sys.exit(f"{method} failed: {message['error']}")
            return message["result"]


def call(tool, **arguments):
    result = request("tools/call", {"name": tool, "arguments": arguments})
    print(f"\n== {tool} {json.dumps(arguments)}{'  [isError]' if result.get('isError') else ''}")
    for index, item in enumerate(result["content"]):
        if item["type"] == "text":
            print(item["text"])
        elif item["type"] == "image":
            data = base64.b64decode(item["data"])
            print(f"<{item['mimeType']} {len(data)} bytes>")
            if args.frames_dir:
                os.makedirs(args.frames_dir, exist_ok=True)
                path = os.path.join(args.frames_dir, f"{tool}-{index}.jpg")
                with open(path, "wb") as f:
                    f.write(data)
                print(f"saved {path}")
    return result


init = request("initialize", {
    "protocolVersion": "2025-06-18",
    "capabilities": {},
    "clientInfo": {"name": "openrecord-smoke-test", "version": "1.0"},
})
proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
proc.stdin.flush()
print(f"server: {init['serverInfo']}  protocol: {init['protocolVersion']}")
print(f"instructions: {init.get('instructions')}")

tools = request("tools/list")["tools"]
print("tools:", ", ".join(f"{t['name']}{' (read-only)' if t.get('annotations', {}).get('readOnlyHint') else ''}" for t in tools))

call("list_recordings", limit=5)
call("get_recording", id="latest")
call("get_transcript", id="latest")
call("search_recordings", query=os.environ.get("OPENRECORD_SMOKE_QUERY", "the"))
call("get_frames", id="latest", count=2, max_width=640)
call("get_recording", id="../../etc")

proc.stdin.close()
proc.wait(timeout=10)
