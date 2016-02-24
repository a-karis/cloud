#!/bin/bash

function flush_heat() {
  echo "Flushing heat ..."
  for table in stack_lock resource_data resource event stack;do 
    mysql heat -e "delete from $table"
  done
}

flush_ironic() {
  echo "Flushing ironic ..."
  for table in ports nodes;do
    mysql ironic -e "delete from $table"
  done
}

state_reset_ironic() {
  echo "Resetting ironic state ..."
  mysql ironic -e "update nodes set provision_state = 'available' WHERE maintenance = 0"
}

flush_nova() {
  echo "Flushing nova ..."
  for table in instance_faults instance_system_metadata instance_info_caches instance_extra instance_actions_events instance_actions block_device_mapping instances compute_nodes;do
    mysql nova -e "delete from $table"
  done
}

delete_nova() {
  echo "Deleting nova ..."
  nova list | grep -v 'ID' | awk '{print $2}' | xargs -I {} nova delete {}
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
_delete_neutron_ports() {
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
_delete_neutron_nets() {
  neutron net-list | grep -v ctlplane | awk '{print $2}' | xargs -I {} neutron net-delete {} 2>/dev/null
}

delete_neutron() {
  echo "Deleting neutron ..."
  _delete_neutron_ports
  _delete_neutron_nets
}

if [ "$1" = '-h' ];then
  echo "Usage: --cleanup | --heat-flush --ironic-flush --nova-flush --nova-delete --neutron-delete --ironic-state-reset"
  exit 0
fi

for arg in "$@";do
  if [ $arg = '--cleanup' ];then
    flush_heat
    delete_nova 
    state_reset_ironic
    delete_neutron
  fi
  if [ $arg = '--heat-flush' ];then
    flush_heat
  fi
  if [ $arg == '--ironic-flush' ];then
    flush_ironic
  fi
  if [ $arg == '--ironic-state-reset' ];then
    state_reset_ironic
  fi
  if [ $arg == '--nova-flush' ];then
    flush_nova
  fi
  if [ $arg == '--nova-delete' ];then
    delete_nova
  fi
  if [ $arg == '--neutron-delete' ];then
    delete_neutron
  fi

  echo 'Restarting ironic ...'
  sudo openstack-service restart ironic
  echo 'Restarting heat ...'
  sudo openstack-service restart heat
done
