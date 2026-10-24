#!/bin/sh
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
if [ "$1" = auth ]; then echo '{"loggedIn":true,"email":"agent@example.com","subscriptionType":"max"}'; exit 0; fi
prompt="$2"
report=$(printf '%s\n' "$prompt" | grep '/debriefs/cycle-')
brief=$(printf '%s\n' "$prompt" | grep '^/.*/handoffs/session-..\.md$')
echo '{"type":"system","subtype":"init","session_id":"sess-1","model":"test-model"}'
if [ -n "$FIRETEAM_TEST_LIMIT" ] && [ -f "$FIRETEAM_TEST_LIMIT" ]; then rm "$FIRETEAM_TEST_LIMIT"
echo '{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":'$(( $(date +%s) + 1 ))',"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":1.0,"status":"rejected"}}}}'
echo '{"type":"result","subtype":"error_during_execution","is_error":true,"result":"You have hit your usage limit · resets 3pm"}'
exit 1; fi
if [ -n "$FIRETEAM_TEST_SLOW" ]; then sleep "$FIRETEAM_TEST_SLOW"; fi
case "$2" in *"OVERWATCH REVIEW"*)
  diff=$(printf '%s\n' "$2" | grep '/reviews/review-..\.diff$')
  [ -n "$diff" ] && cp "$diff" "$FIRETEAM_TEST_LOG.diff"
  if [ -f "$FIRETEAM_TEST_LOG.pass" ]; then grade=pass; else grade=needs-work; touch "$FIRETEAM_TEST_LOG.pass"; fi
  printf '%s\n' '{"type":"result","subtype":"success","is_error":false,"result":"Looked it over.\n```json\n{\"grade\": \"'$grade'\", \"summary\": \"Mostly there.\", \"findings\": [{\"severity\": \"high\", \"file\": \"notes.txt\", \"issue\": \"Add a title line.\"}]}\n```"}'
  exit 0;;
esac
if [ -n "$brief" ]; then echo '# brief' > "$brief"; echo '{"type":"result","subtype":"success","is_error":false,"result":"Brief written.","session_id":"sess-1","total_cost_usd":0.01}'; exit 0; fi
if [ -n "$FIRETEAM_TEST_STALL" ] && [ -f "$FIRETEAM_TEST_STALL" ]; then rm "$FIRETEAM_TEST_STALL"; echo '{"type":"assistant","message":{"usage":{"input_tokens":900000,"output_tokens":0},"content":[]}}'; exec sleep 20; fi
if [ -n "$FIRETEAM_TEST_DENY" ] && ! printf '%s\n' "$@" | grep -qx 'Bash(npm test:\*)'; then
echo '{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"npm test"}}]}}'
echo '{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":true,"content":"This command requires approval"}]}}'
echo '{"type":"result","subtype":"success","is_error":false,"result":"Blocked on npm test.","session_id":"sess-1","permission_denials":[{"tool_name":"Bash","tool_use_id":"t1","tool_input":{"command":"npm test"}}]}'
exit 0
fi
echo '{"type":"assistant","message":{"usage":{"input_tokens":'${FIRETEAM_TEST_CONTEXT:-1000}',"output_tokens":0},"content":[{"type":"text","text":"Moving out."},{"type":"tool_use","name":"Edit","input":{"file_path":"/x/src/main.cpp"}}]}}'
echo "line" >> notes.txt
case "$report" in *cycle-01.html) echo '<html>agent debrief</html>' > "$report";; esac
echo '{"type":"result","subtype":"success","is_error":false,"result":"Cycle done.","session_id":"sess-1","total_cost_usd":0.25,"num_turns":3}'
