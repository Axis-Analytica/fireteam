#!/bin/sh
# A stand-in for `codex exec --json`: records its arguments and prints a turn
# in Codex 0.164's JSONL.
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
cat <<'EOF'
{"type":"thread.started","thread_id":"01a1713c-fe23-77a1-8036-b5c2cabb1f54"}
{"type":"turn.started"}
{"type":"error","message":"Reconnecting... 1/5 (stream disconnected before completion)"}
{"type":"item.started","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc 'make test'","aggregated_output":"","exit_code":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_1","type":"command_execution","command":"/bin/bash -lc 'make test'","aggregated_output":"running 3 tests\n...ok\n","exit_code":0,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_2","type":"reasoning","text":"**Planning the fix**"}}
{"type":"item.completed","item":{"id":"item_3","type":"file_change","changes":[{"path":"/repo/src/lib.rs","kind":"update"}],"status":"completed"}}
{"type":"item.started","item":{"id":"item_4","type":"mcp_tool_call","server":"fireteam","tool":"sitrep","arguments":{"text":"tests pass"},"result":null,"error":null,"status":"in_progress"}}
{"type":"item.completed","item":{"id":"item_4","type":"mcp_tool_call","server":"fireteam","tool":"sitrep","arguments":{"text":"tests pass"},"result":{"content":[{"type":"text","text":"ok"}],"structured_content":null},"error":null,"status":"completed"}}
{"type":"item.completed","item":{"id":"item_5","type":"agent_message","text":"Codex: fixed the parser; all tests pass."}}
{"type":"turn.completed","usage":{"input_tokens":24763,"cached_input_tokens":24448,"cache_write_input_tokens":0,"output_tokens":122,"reasoning_output_tokens":64}}
EOF
