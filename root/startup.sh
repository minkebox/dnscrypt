#! /bin/bash

SERVER1="https://one.one.one.one/dns-query"

#
# Encodes https://... DoH URLs as SDNS://... URLs
#
encode() {
  proto="$(echo $1 | grep :// | sed -e's,^\(.*://\).*,\1,g')"
  url=$(echo $1 | sed -e s,$proto,,g)
  hostport=$(echo $url | cut -d/ -f1)
  host="$(echo $hostport | sed -e 's,:.*,,g')"
  port="$(echo $hostport | sed -e 's,^.*:,:,g' -e 's,.*:\([0-9]*\).*,\1,g' -e 's,[^0-9],,g')"
  path="/$(echo $url | grep / | cut -d/ -f2-)"

  if [ "$port" != "" ]; then
    port=":$port"
  fi
  #echo $host $port $path

  arr=(02 06 00 00 00 00 00 00 00)
  arr+=($(printf %02x ${#port}))
  pos=0
  while [ $pos -lt ${#port} ]; do
    arr+=($(printf %02x \'${port:$pos:1}))
    ((pos++))
  done
  arr+=(00)
  arr+=($(printf %02x ${#host}))
  pos=0
  while [ $pos -lt ${#host} ]; do
    arr+=($(printf %02x \'${host:$pos:1}))
    ((pos++))
  done
  arr+=($(printf %02x ${#path}))
  pos=0
  while [ $pos -lt ${#path} ]; do
    arr+=($(printf %02x \'${path:$pos:1}))
    ((pos++))
  done
  enc=$(echo "${arr[@]}" | xxd -p -r | base64 | sed "s/=*$//")
  echo "sdns://${enc}"
}

# Shift secondary to primary is primary is missing
if [ "${SERVER1}" = "" -a "${SERVER2}" != "" ]; then
  SERVER1=${SERVER2}
  SERVER2=""
fi

# Encode servers
servers=''
if [ "${SERVER1}" != "" ]; then
  case "${SERVER1}" in
    sdns://*)
      ;;
    https://*)
      SERVER1=$(encode "${SERVER1}")
      ;;
  esac
  s1="[static.'_primary']
stamp = '${SERVER1}'"
  servers="'_primary'"
  if [ "${SERVER2}" != "" ]; then
    case "${SERVER2}" in
      sdns://*)
        ;;
      https://*)
        SERVER2=$(encode "${SERVER2}")
        ;;
    esac
    s2="[static.'_secondary']
stamp = '${SERVER2}'"
    servers="'_primary','_secondary'"
  fi
fi

# Enable IPv6 is asked
ipv6_servers=false
block_ipv6=true
if [ "${IP6}" = "true" ]; then
  ipv4_servers=true
  block_ipv6=false
fi

# Generate configuration
cat > /etc/dnscrypt-proxy/dnscrypt-proxy.toml <<__EOF__
max_clients = 250
ipv4_servers = true
ipv6_servers = ${ipv6_servers}
block_ipv6 = ${block_ipv6}
dnscrypt_servers = true
doh_servers = true
require_dnssec = false
require_nolog = false
require_nofilter = false
force_tcp = false
timeout = 5000
keepalive = 30
cert_refresh_delay = 240
blocked_query_response = 'refused'
ignore_system_dns = true
use_syslog = false
log_files_max_size = 1
log_files_max_age = 1
log_files_max_backups = 1
cache = true
cache_size = 1024
cache_min_ttl = 2400
cache_max_ttl = 86400
cache_neg_min_ttl = 60
cache_neg_max_ttl = 600
netprobe_timeout = 60
server_names = [ ${servers} ]
${s1}
${s2}
__EOF__

trap "killall sleep dnscrypt-proxy; exit" TERM INT

/usr/bin/dnscrypt-proxy -config /etc/dnscrypt-proxy/dnscrypt-proxy.toml &

sleep 2147483647d &
wait "$!"
