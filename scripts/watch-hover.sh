#!/usr/bin/env bash
# Live view of shima's hover, layout and display decisions (criteria 3, 4, 5, 8).
exec log stream --level debug --style compact --predicate 'subsystem == "local.shima"'
