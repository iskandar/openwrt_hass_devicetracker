# openwrt_hass_devicetracker

Package for a completely event-driven device/user presence tracker for [Home Assistant](https://github.com/home-assistant/home-assistant/) on an OpenWRT/LEDE access point. 

## Iskandar's Modifications

I wanted to use this in a mixed device tracker environment in a fashion that treats the devices detected by this script separately from other devices. In order to do this, these scripts now can use 'device mode', which maps a MAC address to a device name in the `devices` file.

To enable this mode:

* Edit your `/usr/lib/hass/devices` file
* Set the config setting `use_device_id` to `1`
* Reload the daemon: `/etc/init.d/hass reload`

I tested with this specific OpenWRT version: 

* `OpenWrt 18.06.1 r7258-5eb055306f / LuCI openwrt-18.06 branch (git-18.228.31946-f64b152)`

## Description

Listens on hostapd wifi association events and then initiates appropriate service calls to the configured Home Assistant instance. On `AP-STA-CONNECTED` or `AP-STA-POLL-OK` the device is marked as seen with a timeout set by the `timeout_conn` config option. If an `AP-STA-DISCONNECTED` event is received, it is marked as seen with a timeout of `timeout_disc`.

Since restarting your access points removes any scripts connected via `hostapd_cli -a`, this package includes a daemon which monitors ubus for added APs so restarting/reconfiguring your radios doesn't kill the service.

## Installation

Simple `opkg install hass` once it is added to the OpenWRT repositories. Until then, download a package from releases and `opkg install <downloaded_file>`. Then you can modify `/etc/config/hass` to your liking and start/enable the service via `service hass start` and `service hass enable`.

## Note on missed events

If Home Assistant or the OpenWRT access point is restarted frequently or unreliable in other ways, you should reduce the very long default timeout for connected devices, since a disconnect event may be missed. However, since association events for connected devices can happen as infrequently as every 2-4 hours, you might want to then add a cronjob which synchronizes the state to Home Assistant at least twice as often as your timeout for connected devices `timeout_conn`. A good value for this might be a timeout of 1 hour and a sync every 30 minutes. The cronjob should look like:

```
#!/bin/sh

source "/lib/functions.sh"
config_load hass

source /usr/lib/hass/functions.sh
sync_state
```

This ensures that missed disconnect events do not spuriously keep the device present for more than an hour. This will be implemented by default in a future version or via an OpenWRT DeviceScanner in Home Assistant.
