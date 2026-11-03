#!/bin/bash
# Sends one test command to a running Nox (a build made from source). Example: tests/post-test.sh popshot:light
osascript -l JavaScript -e 'ObjC.import("Foundation"); function run(a){ $.NSDistributedNotificationCenter.defaultCenter.postNotificationNameObjectUserInfoDeliverImmediately("com.solomon.DarkSwitch.test", a[0], $(), true); }' "$1"
