set -x

function err_msg {
    logger -t $0 -p error $@
    echo $1 1>&2
}

function register_hook {
    logger -t $0 -p debug "register_hook $@"
    if [ "$#" -ne 1 ]; then
        err_msg "register_hook missing interface"
        exit 1
    fi
    interface=$1
    
    hostapd_cli -i$interface -a/usr/lib/hass/push_event.sh &
}

function post {
    if [ -z $@ ]; then
        # logger -t $0 -p warning "No payload found"
       return
    fi
    if [ "$#" -ne 1 ]; then
        # err_msg "POST missing payload"
        return
    fi
    payload=$1
    if [ -z $payload ]; then
        # logger -t $0 -p warning "No payload found"
        return
    fi
    logger -t $0 -p debug "post $@"
    
    config_get hass_host global host
    config_get hass_token global token "0"
    config_get hass_pw global pw "0"
    
    auth_head="X-No-Auth-Needed: true"
    if [ "$hass_token" != "0" ]; then
        auth_head="Authorization: Bearer $hass_token"
    fi
    if [ "$hass_pw" != "0" ]; then
        auth_head="X-HA-Access: $hass_pw"
    fi
    
    resp=$(curl "$hass_host/api/services/device_tracker/see" -sfSX POST \
        -H 'Content-Type: application/json' \
        -H "$auth_head" \
        --data-binary "$payload" 2>&1)
    
    if [ $? -eq 0 ]; then
        level=debug
    else
        level=error
    fi    
    logger -t $0 -p $level "post response $resp"
}

function build_mac_payload {
    # logger -t $0 -p debug "build_mac_payload $@"
    if [ "$#" -ne 3 ]; then
        err_msg "Invalid payload parameters"
        logger -t $0 -p warning "push_event not handled"
       return
    fi
    mac=$1
    host=$2
    consider_home=$3

    echo "{\"mac\":\"$mac\",\"host_name\":\"$host\",\"consider_home\":\"$consider_home\",\"source_type\":\"router\"}"
}

function build_device_payload {
    # logger -t $0 -p debug "build_device_payload $@"
    if [ "$#" -ne 2 ]; then
        err_msg "Invalid payload parameters"
        logger -t $0 -p warning "push_event not handled"
        return
    fi
    device_id=$1
    consider_home=$2    
    if [ -z "$device_id" ]; then
        #logger -t $0 -p warning "No device id found"
        return
    fi
    echo "{\"dev_id\":\"$device_id\",\"consider_home\":\"$consider_home\",\"source_type\":\"router\"}"
}

function get_ip {
    # get ip for mac
    grep "0x2\s\+$1" /proc/net/arp | cut -f 1 -s -d" "
}

function get_host_name {
    # get hostname for mac
    config_get dns_server global dns_server
    nslookup "$(get_ip $1 $dns_server)" | grep name | awk '{print $4}'
}

function is_connected {
    # check if MAC address is still connected to any wireless interface
    mac=$1

    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        if iw dev $interface station dump | grep Station | grep -q $mac; then
            return 0
        fi
    done

    return 1
}

function get_device_id {
    # get device for mac 
    grep -i "$1" /usr/lib/hass/devices | awk '{print $2}'
}

function push_event {
    logger -t $0 -p debug "push_event $@"
    if [ "$#" -ne 3 ]; then
        err_msg "Illegal number of push_event parameters"
        exit 1
    fi
    iface=$1
    msg=$2
    mac=$3
    
    config_get hass_timeout_conn global timeout_conn
    config_get hass_timeout_disc global timeout_disc
    config_get hass_use_device_id global use_device_id
    
    status="unknown"

    case $msg in 
        "AP-STA-CONNECTED")
            timeout=$hass_timeout_conn
            status="connected"
            ;;
        "AP-STA-POLL-OK")
            timeout=$hass_timeout_conn
            status="connected"
            ;;
        "AP-STA-DISCONNECTED")
            timeout=$hass_timeout_disc
            status="disconnected"
            if is_connected $mac; then
                logger -t $0 -p debug "push_event ignored as device is still online"
                status="connected"
            fi
            ;;
        *)
            logger -t $0 -p warning "push_event not handled"
            return
            ;;
    esac

    device_id=$(get_device_id $mac)
    if [ "$device_id" != "" ]; then
        hostname=$(get_host_name $mac)
        logger -t $0 -p debug "$mac $hostname $device_id"
        if [ "$hass_use_device_id" = "1" ]; then
            post $(build_device_payload "$device_id" "$timeout")
        else
            post $(build_mac_payload "$mac" "$hostname" "$timeout")
        fi
            
        config_get hass_use_mqtt global use_mqtt
        if [ -n $hass_use_mqtt ]; then
            publish_mqtt "$status" "$mac" "$hostname" "$device_id"
        fi
    fi
}

function publish_mqtt {
    status=$1
    mac=$2
    hostname=$3
    device_id=$4

    config_get mqtt_url mqtt url
    config_get mqtt_client_id_base mqtt client_id_base
    config_get mqtt_topic_base mqtt topic_base
    # Not sure how to use config_get, so we just shell out
    source_hostname=`uci get system.@system[0].hostname`

    # Build a JSON payload
    msg="{\"device\":\"$device_id\",\"mac\":\"$mac\",\"hostname\":\"$hostname\",\"status\":\"$status\",\"source\":\"$source_hostname\"}"    
    logger -t $0 -p debug "MQTT: $msg"
    mosquitto_pub -L $mqtt_url -I $mqtt_client_id_base -t $mqtt_topic_base -m $msg
}

function sync_state {
    logger -t $0 -p debug "sync_state $@"
    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
        for mac in $maclist; do
            # Fake a 'poll ok' message
            push_event $interface "AP-STA-POLL-OK" $mac &
        done
    done
}

function write_state {
    # logger -t $0 -p debug "write_state"
    count=0
    for interface in `iw dev | grep Interface | cut -f 2 -s -d" "`; do
        maclist=`iw dev $interface station dump | grep Station | cut -f 2 -s -d" "`
        for mac in $maclist; do
           count=$(($count+1))
        done
    done
    logger -t $0 -p debug "write state, station count: $count"

    config_get mqtt_url mqtt url
    config_get mqtt_client_id_base mqtt client_id_base
    config_get mqtt_topic_base mqtt topic_base
    # Not sure how to use config_get, so we just shell out
    source_hostname=`uci get system.@system[0].hostname`

    mosquitto_pub -L $mqtt_url -I $mqtt_client_id_base \
         -t $mqtt_topic_base/$source_hostname -r -m $count
}
