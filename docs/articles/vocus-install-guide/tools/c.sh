#!/bin/bash
# usage: c.sh action '{"k":"v"}'
body=$(python3 -c 'import json,sys; d=json.loads(sys.argv[2]) if len(sys.argv)>2 and sys.argv[2] else {}; d["action"]=sys.argv[1]; print(json.dumps(d))' "$@")
curl -s --max-time 120 -X POST http://127.0.0.1:9333 -d "$body"
echo
