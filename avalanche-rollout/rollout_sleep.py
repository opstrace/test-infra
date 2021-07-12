#!/usr/bin/python3

# Copyright 2021 Opstrace, Inc.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Rollout sleep scheduler
# This script is meant to be called from a StatefulSet pod before starting the main command.
# The script will invoke a sleep command until the next time that the command should be started.
# This ensures that a command across pods is started on an even rollout schedule.
#
# Options (envvars):
# - POD_NAME: The name of the pod, must end in a StatefulSet-like index (e.g. "pod-name-49")
# - REPLICAS: The number of replicas in the StatefulSet
# - STAGGER_MINS: The desired period between pod N starting and pod N+1 starting
# - DRY_RUN (optional): If non-empty, the sleep duration is printed, but the sleep itself is skipped
#
# Example:
#   10 pods, each separated by 5 minutes for a 50 minute rollout, with the current time at 3:45
#   If the current rollout starts at 3:30, and this is pod index 4, then the script will sleep until 3:50 and exit
#   However, if we're already at 3:55, then the next rollout starts at 4:20 and this script will exit at 4:40

import math, os, re, time


def getenv_int(env_name):
    value = os.getenv(env_name)
    if not value:
        raise Exception("Missing {} environment variable".format(env_name))
    try:
        return int(value)
    except:
        raise Exception("Expected {} to be an integer: {}".format(env_name, value))


# determine the pod index (expecting it to be in a StatefulSet)
pod_name = os.getenv("POD_NAME")
if not pod_name:
    raise Exception("Missing POD_NAME environment variable")
pod_index_match = re.match(r"^.+-([0-9]+)$", pod_name)
if not pod_index_match:
    raise Exception(
        "Expected POD_NAME to end in '-[0-9]+', is this a StatefulSet?: {}".format(
            pod_name
        )
    )
pod_index = int(pod_index_match.group(1))

# among REPLICAS pods, we want one pod to restart every STAGGER_MINS
replicas = getenv_int("REPLICAS")
stagger_secs = 60 * getenv_int("STAGGER_MINS")
if replicas <= 0 or stagger_secs <= 0:
    raise Exception(
        "REPLICAS={} and STAGGER_MINS={} must be greater than 0".format(
            replicas, stagger_secs / 60
        )
    )
if replicas <= pod_index:
    raise Exception(
        "REPLICAS={} must be larger than index in POD_NAME={}".format(
            replicas, pod_name
        )
    )
print("Pod: {} => {} of {}".format(pod_name, pod_index, replicas))

# figure out when our pod is expected to next restart, relative to current time
now_time = math.floor(time.time())
print("Now: {}".format(time.ctime(now_time)))

# math:
# we want R replicas to staggered-start every S seconds -> rollout cycle should take R*S seconds
rollout_duration_secs = replicas * stagger_secs

# to figure out when the rollout starts, lets just use a modulo of the current time
# e.g. current time 12345 and duration 600 => current cycle starts at 12000
rollout_start_time = now_time - (now_time % rollout_duration_secs)

# next figure out when this pod should start within the rollout,
# e.g. start 12000 and duration 600 and current pod
pod_start_secs = math.floor(pod_index * rollout_duration_secs / replicas)

pod_start_time = rollout_start_time + pod_start_secs
if pod_start_time < now_time:
    # pod start time is in the past for this cycle, so skip forward to next cycle
    print(
        "Too-early rollout of {} pods starts at: {}, with pod {} starting at: {}".format(
            replicas,
            time.ctime(rollout_start_time),
            pod_index,
            time.ctime(pod_start_time),
        )
    )
    rollout_start_time += rollout_duration_secs
    pod_start_time += rollout_duration_secs
print(
    "Matching rollout of {} pods starts at: {}, with pod {} starting at: {}".format(
        replicas, time.ctime(rollout_start_time), pod_index, time.ctime(pod_start_time)
    )
)

sleep_secs = pod_start_time - now_time
if os.getenv("DRY_RUN"):
    print("DRY_RUN: Would have slept for {}s".format(sleep_secs))
else:
    print("Sleeping for {}s...".format(sleep_secs))
    time.sleep(sleep_secs)
