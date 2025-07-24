#!/usr/bin/env bash
set -e
echo "✅ frontend -> backend (should pass)"; echo
kubectl exec frontend -- wget -qO- backend | head -1
echo
echo "✅ intruder -> backend (should fail)"; echo
kubectl exec intruder -- wget -qO- --timeout=3 backend >/dev/null 2>&1 && \
  echo "❌ succeeded" || echo "Blocked"