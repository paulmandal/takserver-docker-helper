#!/bin/bash -e
source helper-script.conf

echo "Before you run this script: "
echo " - Edit your tak/CoreConfig.xml and set a db password"
echo " - Add the SSL input if you want it and comment out the others if you don't want them:"
echo '         <input _name="stdssl" protocol="tls" port="8089" auth="x509"/>'
echo " - Edit tak/certs/cert-metadata.sh"

confirmContinue=n
echo -n "Enter Y to continue: "
read confirmContinue

if [ "${confirmContinue}" != "y" -a "${confirmContinue}" != "Y" ]
then
  exit 1
fi

cd "`echo ${targetZip} | sed 's/\.zip//'`"

docker build -t takserver-db:${takServerVersion} -f docker/Dockerfile.takserver-db . \
&& docker network create takserver-net-${takServerVersion} \
&& mkdir tak-db \
&& docker run -d -v $(pwd)/tak-db:/var/lib/postgresql/data:z -v $(pwd)/tak:/opt/tak:z -it -p 5432:5432 --network takserver-net-${takServerVersion} --restart unless-stopped --network-alias tak-database --name takserver-db-${takServerVersion} takserver-db:${takServerVersion} \
&& sudo docker build -t takserver:${takServerVersion} -f docker/Dockerfile.takserver . \
&& docker run -d -v $(pwd)/tak:/opt/tak:z -it -p 8080:8080 -p 8443:8443 -p 8444:8444 -p 8446:8446 -p 8087:8087 -p 8088:8088 -p 9000:9000 -p 9001:9001 -p 8089:8089 --restart unless-stopped --network takserver-net-${takServerVersion} --name takserver-${takServerVersion} takserver:${takServerVersion} \
&& docker exec -it takserver-${takServerVersion} bash -c "cd /opt/tak/certs && ./makeRootCa.sh" \
&& docker exec -it takserver-${takServerVersion} bash -c "cd /opt/tak/certs && ./makeCert.sh server takserver"
