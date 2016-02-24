#!/bin/bash

function flush_heat() {
  for table in resource_data resource event stack;do 
    mysql heat -e "delete from $table"
  done
}

flush_ironic() {
  for table in ports nodes;do
    mysql ironic -e "delete from $table"
  done
}

flush_nova() {
  for table in instance_faults instance_system_metadata instance_info_caches instance_extra instance_actions_events instance_actions block_device_mapping instances compute_nodes;do
    mysql nova -e "delete from $table"
  done
}

_get_ctlplane_network() {
  neutron net-list | grep ctlplane | awk '{print $(NF-1)}'
}

_ip2int() {
    local a b c d
    { IFS=. read a b c d; } <<< $1
    echo $(((((((a << 8) | b) << 8) | c) << 8) | d))
}

_pl2mask() {
  echo $[ (1 << 32) - (1 << (32 - $1))]
}

_is_on_net() {
  local ip_address=$1
  local ip_address_int=$(_ip2int $ip_address)
  local network_prefix=$(echo "$2" | awk -F '/' '{print $1}')
  local network_prefix_int=$(_ip2int $network_prefix)
  local pl=$(echo "$2" | awk -F '/' '{print $2}')
  local mask=$(_pl2mask $pl)

  [ $[$ip_address_int & $mask] = $[$network_prefix_int & $mask] ] 
}

# flush all ports with the exception of ctlplane port DHCP
_flush_neutron_ports() {
  ctl_plane_network=$(_get_ctlplane_network)
  neutron port-list | egrep '[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}' | while read line;do
    ip_address=`echo $line | awk -F '"' '{print $(NF-1)}'`
    port_id=`echo $line | awk '{print $2}'`
    if ! $(_is_on_net $ip_address $ctl_plane_network);then
      neutron port-delete $port_id
    else
      if ! `neutron port-show $port_id | grep -q 'network:dhcp'`;then
        neutron port-delete $port_id
      fi
    fi
  done  
}

# flush all nets with exception of DHCP
_flush_neutron_nets() {
  neutron net-list | grep -v ctlplane | awk '{print $2}' | xargs -I {} neutron net-delete {} 2>/dev/null
}

flush_neutron() {
  _flush_neutron_ports
  _flush_neutron_nets
}

for arg in "$@";do
  if [ $arg = '--heat' ];then
    echo "Flushing heat ..."
    flush_heat
  fi
  if [ $arg == '--ironic' ];then
    echo "Flushing ironic ..."
    flush_ironic
  fi
  if [ $arg == '--nova' ];then
    echo "Flushing nova ..."
    flush_nova
  fi
  if [ $arg == '--neutron' ];then
    echo "Flushing neutron ..."
    flush_neutron
  fi
done
