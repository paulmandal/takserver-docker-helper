#!/bin/bash -e
source helper-script.conf

if [ ! -f "${targetZip}" ]; then
  echo "You must be in the same directory as ${targetZip}"
  exit 1
fi

# install Docker
sudo apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release

sudo mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/${systemType}/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${systemType} \
  $(lsb_release -cs) stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

sudo apt update
sudo apt install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin

sudo usermod -aG docker $USER

sudo apt install -y unzip

# unzip TAKServer
unzip ${targetZip}
cd "`echo ${targetZip} | sed 's/\.zip//'`"

mkdir client-pkg

# fix TAKServer Docker for Postgres 14.4
sed -i "s/FROM postgres:.*/FROM postgres:14.4/" docker/Dockerfile.takserver-db
sed -i "s/postgresql-10-postgis-2.4/postgresql-14-postgis-3/" docker/Dockerfile.takserver-db
sed -i "s/RUN echo/#RUN echo/" docker/Dockerfile.takserver-db
sed -i $'s/^\tapt update/RUN apt update/' docker/Dockerfile.takserver-db
sed -i "s/-t stretch-backports//" docker/Dockerfile.takserver-db
sed -i "s#postgresql/10/#postgresql/14/#g" tak/db-utils/configureInDocker.sh

# create some useful scripts
tee -a mk-client-cert.sh <<EOF > /dev/null
#!/bin/bash
if [ -z "\${1}" ]
then
  echo "Usage \${0} <client name>"
  exit 1
fi

docker exec -it takserver-${takServerVersion} bash -c "cd /opt/tak/certs && ./makeCert.sh client \${1}"
EOF
chmod a+x mk-client-cert.sh

tee -a reload-certs.sh <<EOF > /dev/null
#!/bin/bash
docker exec -d takserver-${takServerVersion} bash -c "cd /opt/tak/ && ./configureInDocker.sh"
EOF
chmod a+x reload-certs.sh

tee -a create-http-user.sh <<EOF > /dev/null
#!/bin/bash
if [ -z "\${1}" -o -z "\${2}" ]
then
  echo "Usage \${0} <username> <password>"
  exit 1
fi

docker exec takserver-${takServerVersion} bash -c "cd /opt/tak/ && java -jar /opt/tak/utils/UserManager.jar usermod -A -p \${2} \${1}"
EOF
chmod a+x create-http-user.sh

tee -a add-webadmin-role-to-cert.sh <<EOF > /dev/null
#!/bin/bash
if [ -z "\${1}" ]
then
  echo "Usage \${0} <client name>"
  exit 1
fi

docker exec takserver-${takServerVersion} bash -c "cd /opt/tak/ && java -jar utils/UserManager.jar certmod -A certs/files/\${1}.pem"
EOF
chmod a+x add-webadmin-role-to-cert.sh

tee -a mk-server-conn-pkg.sh <<OUTEREOF > /dev/null
#!/bin/bash
if [ -z "\${1}" -o -z "\${2}" -o -z "\${3}" -o -z "\${4}" ]
then
  echo "Usage \${0} <client name> \"<server name>\" <takserver address:port:proto> <ios/android>"
  echo " e.g. \${0} someUser \"Our TAK Server\" takserver.fakeaddress.fake:8089:ssl ios"
  exit 1
fi

if [ "\${4}" != "ios" -a "\${4}" != "android" ]
then
  echo "Usage \${0} <client name> \"<server name>\" <takserver address:port:proto> <ios/android>"
  echo " e.g. \${0} someUser \"Our TAK Server\" takserver.fakeaddress.fake:8089:ssl ios"
  exit 1
fi

clientName=\${1}
serverName=\${2}
connString=\${3}
pkgType=\${4}

manifestUuid=`cat /proc/sys/kernel/random/uuid`

destDir=`pwd`/client-pkg
workingDir="/tmp/tak-server-`date +%s`-\${clientName}"

mkdir "/tmp/tak-server-`date +%s`-\${clientName}"

sudo cp "tak/certs/files/\${clientName}.p12" "\${workingDir}"
sudo cp "tak/certs/files/truststore-root.p12" "\${workingDir}"

pushd "\${workingDir}"

if [ "\${pkgType}" == "android" ]
then
  manifestPath="MANIFEST/manifest.xml"
  certPath="/storage/emulated/0/atak/cert"
  mkdir MANIFEST
else
  certPath="certs"
  manifestPath="manifest.xml"
fi

tee -a \${manifestPath} <<EOF > /dev/null
<MissionPackageManifest version="2">
   <Configuration>
      <Parameter name="uid" value="\${manifestUuid}"/>
      <Parameter name="name" value="\${serverName}"/>
      <Parameter name="onReceiveDelete" value="true"/>
   </Configuration>
   <Contents>
      <Content ignore="false" zipEntry="preference.pref"/>
      <Content ignore="false" zipEntry="truststore-root.p12"/>
      <Content ignore="false" zipEntry="\${clientName}.p12"/>
   </Contents>
</MissionPackageManifest>
EOF

tee -a preference.pref <<EOF > /dev/null
<?xml version='1.0' encoding='ASCII' standalone='yes'?>
<preferences>
	<preference version="1" name="cot_streams">
		<entry key="count" class="class java.lang.Integer">1</entry>
		<entry key="description0" class="class java.lang.String">\${serverName}</entry>
		<entry key="enabled0" class="class java.lang.Boolean">true</entry>
		<entry key="connectString0" class="class java.lang.String">\${connString}</entry>
	</preference>
	<preference version="1" name="com.atakmap.app_preferences">
		<entry key="displayServerConnectionWidget" class="class java.lang.Boolean">true</entry>
		<entry key="caLocation" class="class java.lang.String">/storage/emulated/0/atak/cert/truststore-root.p12</entry>
		<entry key="certificateLocation" class="class java.lang.String">\${certPath}/\${clientName}.p12</entry>
    <entry key="caPassword" class="class java.lang.String">atakatak</entry>
		<entry key="clientPassword" class="class java.lang.String">atakatak</entry>
	</preference>
</preferences>
EOF

sudo chmod 666 ./*p12
zip -qr "\${destDir}/takserver-conn-pkg-\${clientName}.zip" ./*
popd
rm -rf "\${workingDir}"
echo "Created \${destDir}/takserver-conn-pkg-\${clientName}.zip"
OUTEREOF
chmod a+x mk-server-conn-pkg.sh

# Update system and reboot
sudo apt upgrade -y
sudo apt autoremove -y

echo "Updated system, rebooting!"
sudo reboot
