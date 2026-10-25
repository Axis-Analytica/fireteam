#!/bin/sh
# A stand-in for `opencode run --format json`: records its arguments and its
# inline config, and prints a session in OpenCode 1.19's JSON events, which
# have no result event. An overwatch prompt gets a verdict.
printf '%s\n' "$@" >> "$FIRETEAM_TEST_LOG"
echo "CONFIG:$OPENCODE_CONFIG_CONTENT" >> "$FIRETEAM_TEST_LOG"
echo '---' >> "$FIRETEAM_TEST_LOG"
case "$*" in *"OVERWATCH REVIEW"*)
cat <<'EOF'
{"type":"step_start","timestamp":1792901650000,"sessionID":"ses_review0000000000000000000","part":{"id":"prt_1","sessionID":"ses_review0000000000000000000","messageID":"msg_1","type":"step-start"}}
{"type":"text","timestamp":1792901650900,"sessionID":"ses_review0000000000000000000","part":{"id":"prt_2","sessionID":"ses_review0000000000000000000","messageID":"msg_1","type":"text","text":"Looked it over.\n```json\n{\"grade\": \"pass\", \"summary\": \"Sound work.\", \"findings\": []}\n```","time":{"start":1792901650100,"end":1792901650900}}}
{"type":"step_finish","timestamp":1792901651000,"sessionID":"ses_review0000000000000000000","part":{"id":"prt_3","sessionID":"ses_review0000000000000000000","messageID":"msg_1","type":"step-finish","reason":"stop","cost":0.005,"tokens":{"total":1000,"input":900,"output":100,"reasoning":0,"cache":{"read":0,"write":0}}}}
EOF
exit 0;;
esac
cat <<'EOF'
{"type":"step_start","timestamp":1792901650000,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_a","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"step-start","snapshot":"4b825dc6"}}
{"type":"text","timestamp":1792901650900,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_b","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"text","text":"Running the tests first.","time":{"start":1792901650100,"end":1792901650900}}}
{"type":"tool_use","timestamp":1792901655000,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_c","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"tool","callID":"toolu_01AbC","tool":"bash","state":{"status":"completed","input":{"command":"npm test","description":"Run tests"},"output":"12 passing\n","title":"npm test","metadata":{"exit":0},"time":{"start":1792901651000,"end":1792901655000}}}}
{"type":"tool_use","timestamp":1792901656000,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_d","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"tool","callID":"toolu_01Def","tool":"edit","state":{"status":"completed","input":{"filePath":"/repo/src/main.ts","oldString":"a","newString":"b"},"output":"","time":{"start":1792901655500,"end":1792901656000}}}}
{"type":"tool_use","timestamp":1792901656500,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_e","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"tool","callID":"toolu_01Ghi","tool":"fireteam_sitrep","state":{"status":"completed","input":{"status":"tests pass"},"output":"ok","time":{"start":1792901656100,"end":1792901656500}}}}
{"type":"step_finish","timestamp":1792901657000,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_f","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_a","type":"step-finish","reason":"tool-calls","cost":0.01,"tokens":{"total":25010,"input":1200,"output":310,"reasoning":0,"cache":{"read":23500,"write":0}}}}
{"type":"text","timestamp":1792901658000,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_g","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_b","type":"text","text":"OpenCode: tests pass and the edit is in.","time":{"start":1792901657500,"end":1792901658000}}}
{"type":"step_finish","timestamp":1792901658500,"sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","part":{"id":"prt_h","sessionID":"ses_e8ebc0345ffe364cd4gpUHWbQu","messageID":"msg_b","type":"step-finish","reason":"stop","cost":0.02,"tokens":{"total":26000,"input":300,"output":200,"reasoning":0,"cache":{"read":25000,"write":500}}}}
EOF
