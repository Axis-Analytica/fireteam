#!/bin/sh
# A stand-in for `gemini -p -o stream-json`: records its arguments, the policy
# it was given and the field link in its home, and prints a run in Gemini CLI
# 0.65's stream-json. With FIRETEAM_TEST_DENY set, npm test is refused unless
# the policy allows it.
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
policy=""
prev=""
for a in "$@"; do [ "$prev" = "--policy" ] && policy="$a"; prev="$a"; done
if [ -n "$policy" ]; then echo "POLICY:"; cat "$policy"; fi >> "$FIRETEAM_TEST_LOG"
if [ -n "$GEMINI_CLI_HOME" ]; then echo "SETTINGS:"; cat "$GEMINI_CLI_HOME/.gemini/settings.json"; echo "ARG2:$FIRETEAM_MCP_ARG_2"; fi >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
cat <<'EOF'
{"type":"init","timestamp":"2026-10-25T04:10:00.000Z","session_id":"11111111-2222-3333-4444-555555555555","model":"gemini-3-pro-preview"}
{"type":"message","timestamp":"2026-10-25T04:10:00.100Z","role":"user","content":"OPERATION"}
{"type":"message","timestamp":"2026-10-25T04:10:01.000Z","role":"assistant","content":"I'll start by surveying","delta":true}
{"type":"message","timestamp":"2026-10-25T04:10:01.100Z","role":"assistant","content":" the project layout.","delta":true}
{"type":"tool_use","timestamp":"2026-10-25T04:10:02.000Z","tool_name":"run_shell_command","tool_id":"run_shell_command-1792901643765-3f2a","parameters":{"command":"make check","description":"Run checks"}}
{"type":"tool_result","timestamp":"2026-10-25T04:10:03.000Z","tool_id":"run_shell_command-1792901643765-3f2a","status":"success","output":"Command: make check\nExit Code: 0"}
{"type":"tool_use","timestamp":"2026-10-25T04:10:04.000Z","tool_name":"replace","tool_id":"replace-1792901644000-aa11","parameters":{"file_path":"/repo/src/app.py","old_string":"a","new_string":"b"}}
{"type":"tool_result","timestamp":"2026-10-25T04:10:04.500Z","tool_id":"replace-1792901644000-aa11","status":"success","output":"ok"}
{"type":"tool_use","timestamp":"2026-10-25T04:10:05.000Z","tool_name":"mcp_fireteam_sitrep","tool_id":"mcp_fireteam_sitrep-1792901645000-bb22","parameters":{"status":"checks pass","progress":50}}
{"type":"tool_result","timestamp":"2026-10-25T04:10:05.500Z","tool_id":"mcp_fireteam_sitrep-1792901645000-bb22","status":"success","output":"ok"}
EOF
if [ -n "$FIRETEAM_TEST_DENY" ] && ! grep -qs 'npm test' "$policy"; then
cat <<'EOF'
{"type":"tool_use","timestamp":"2026-10-25T04:10:06.000Z","tool_name":"run_shell_command","tool_id":"run_shell_command-1792901646000-cc33","parameters":{"command":"npm test"}}
{"type":"tool_result","timestamp":"2026-10-25T04:10:06.100Z","tool_id":"run_shell_command-1792901646000-cc33","status":"error","output":"Tool execution denied by policy.","error":{"type":"policy_violation","message":"Tool execution denied by policy."}}
EOF
fi
cat <<'EOF'
{"type":"message","timestamp":"2026-10-25T04:10:07.000Z","role":"assistant","content":"Gemini: checks","delta":true}
{"type":"message","timestamp":"2026-10-25T04:10:07.100Z","role":"assistant","content":" are green.","delta":true}
{"type":"result","timestamp":"2026-10-25T04:10:08.000Z","status":"success","stats":{"total_tokens":48210,"input_tokens":46900,"output_tokens":1310,"cached":31000,"input":15900,"duration_ms":41234,"tool_calls":3}}
EOF
