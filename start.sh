#!/bin/bash

function abort() {
      exit 1
}

set -mx

mkdir -p /etc/guacamole
/opt/guacamole/sbin/guacd -l "${GUACD_PORT:-4822}" -b 0.0.0.0 -L info -f &
java -jar /guacamole-jetty.jar &

trap abort SIGINT
trap abort SIGTERM

wait -fn
exit $?
