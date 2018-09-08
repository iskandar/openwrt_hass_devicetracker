#!/bin/bash

#
# Quick and dirty script to deploy scripts to an OpenWRT router
# * You'll want to set up SSH keys to make this not drive you insane

set -x

TARGET=${1:root@router}
BASE=./packages/net/hass/files

scp $BASE/hassd.sh $TARGET:/usr/bin/

ssh $TARGET mkdir -p /usr/lib/hass
scp $BASE/{functions.sh,push_event.sh,sync_state.sh,devices} $TARGET:/usr/lib/hass/

ssh $TARGET "cat > /etc/config/hass"   < $BASE/hass.conf
ssh $TARGET "cat > /etc/init.d/hass"   < $BASE/hass.init
ssh $TARGET "cat > /etc/crontabs/root" < $BASE/crontab

ssh $TARGET /bin/sh << EOF
chmod +x /usr/bin/hassd.sh
chmod +x /usr/lib/hass/*.sh
chmod +x /etc/init.d/hass
/etc/init.d/hass reload
/etc/init.d/cron reload
EOF
