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
echo "Unzipping TAK Server package..."
unzip -q ${targetZip}
cd "`echo ${targetZip} | sed 's/\.zip//'`"

mkdir client-data-pkgs

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

tee -a mk-client-dp.sh <<EOF > /dev/null
#!/bin/bash
if [ \$# -eq 0 ]; then
    printf "Usage: \${0} <client>"
    exit
fi

# Check for missing requirements
missingreq=0
for req in printf tr zip docker
do
    if [ -z \$(which \${req}) ]; then
        printf "This script requires \${req}.  Please install it first.\n"
        ((missingreq++))
    fi
done
if [ \$missingreq -gt 0 ]; then
    exit
fi
client=\$1

# Load variables from config file
if [ -f client-dp.conf ]; then
    printf "Loading configuration file.\n"
    . client-dp.conf
else
    printf "Configuration file not found.  Creating a new one.\n"
fi

# Check that all configuration variables loaded successfully
if [ -z "\${servername}" ]; then
    printf "Enter a server name to be displayed in TAK clients. (Default is TAK Server)\n"
    read servername
    if [ -z "\${servername}" ]; then
        servername="TAK Server"
    fi
    printf "servername=\"\${servername}\"\n" >> client-dp.conf
fi
if [ -z "\${serveraddress}" ]; then
    printf "Enter the server's hostname or IP address.  This must be accessible to TAK clients. (Default is \$(hostname))\n"
    read serveraddress
    if [ -z "\${serveraddress}" ]; then
        serveraddress=\$(hostname)
    fi
    printf "serveraddress=\"\${serveraddress}\"\n" >> client-dp.conf
fi
if [ -z "\${serverport}" ]; then
    printf "Enter the SSL port number.  (Default is 8089)\n"
    read serverport
    if [ -z "\${serverport}" ]; then
        serverport="8089"
    fi
    printf "serverport=\"\${serverport}\"\n" >> client-dp.conf
fi
if [ -z "\${takcontainer}" ]; then
    printf "Enter the name of the TAK Server's docker container. (Default is takserver-4.7)\n"
    read takcontainer
    if [ -z "\${takcontainer}" ]; then
        takcontainer="takserver-4.7"
    fi
    printf "takcontainer=\"\${takcontainer}\"\n" >> client-dp.conf
fi

# If client name includes spaces, replace them with dashes
tr ' ' '-' <<<"\$client"
uid=\$(cat /proc/sys/kernel/random/uuid)
dpname=\$(printf "\${servername}-DP" | tr ' ' '-')
mkdir \$client

#Stop if target directory exists
if [ \$? -ne 0 ]; then
  printf "Error creating directory.  Do you already have a directory called \${client}?\nThe script will now stop to avoid data loss.\n"
  exit
fi

# Create the client certs in the TAK container
if [ ! -f "tak/certs/files/\${client}.p12" ]
then
  docker exec -it \${takcontainer} bash -c "cd /opt/tak/certs && ./makeCert.sh client \${client}"
fi

# Create the data package manifest file
printf "<MissionPackageManifest version=\"2\">\n" > \${client}/manifest.xml
printf "  <Configuration>\n" >> \${client}/manifest.xml
printf "    <Parameter name=\"uid\" value=\"\${uid}\"/>\n" >> \${client}/manifest.xml
printf "    <Parameter name=\"name\" value=\"\${dpname}\"/>\n" >> \${client}/manifest.xml
printf "    <Parameter name=\"onReceiveDelete\" value=\"true\"/>\n" >> \${client}/manifest.xml
printf "  </Configuration>\n" >> \${client}/manifest.xml
printf "  <Contents>\n" >> \${client}/manifest.xml
printf "    <Content ignore=\"false\" zipEntry=\"certs/preference.pref\"/>\n" >> \${client}/manifest.xml
printf "    <Content ignore=\"false\" zipEntry=\"certs/takserver-\${uid}.p12\"/>\n" >> \${client}/manifest.xml
printf "    <Content ignore=\"false\" zipEntry=\"certs/\${client}-\${uid}.p12\"/>\n" >> \${client}/manifest.xml
printf "  </Contents>\n" >> \${client}/manifest.xml
printf "</MissionPackageManifest>\n" >> \${client}/manifest.xml

# Create the pref file
printf "<?xml version='1.0' encoding='ASCII' standalone='yes'?>\n" > \${client}/preference.pref
printf "<preferences>\n" >> \${client}/preference.pref
printf "  <preference version=\"1\" name=\"cot_streams\">\n" >> \${client}/preference.pref
printf "    <entry key=\"count\" class=\"class java.lang.Integer\">1</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"description0\" class=\"class java.lang.String\">\${servername}</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"enabled0\" class=\"class java.lang.Boolean\">true</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"connectString0\" class=\"class java.lang.String\">\${serveraddress}:\${serverport}:ssl</entry>\n" >> \${client}/preference.pref
printf "  </preference>\n" >> \${client}/preference.pref
printf "  <preference version=\"1\" name=\"com.atakmap.app_preferences\">\n" >> \${client}/preference.pref
printf "    <entry key=\"displayServerConnectionWidget\" class=\"class java.lang.Boolean\">true</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"caLocation\" class=\"class java.lang.String\">cert/takserver-\${uid}.p12</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"caPassword\" class=\"class java.lang.String\">atakatak</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"clientPassword\" class=\"class java.lang.String\">atakatak</entry>\n" >> \${client}/preference.pref
printf "    <entry key=\"certificateLocation\" class=\"class java.lang.String\">cert/\${client}-\${uid}.p12</entry>\n" >> \${client}/preference.pref
printf "  </preference>\n" >> \${client}/preference.pref
printf "</preferences>\n" >> \${client}/preference.pref

# Copy the truststore and client certs - append a unique ID to avoid filename collisions
docker cp \${takcontainer}:/opt/tak/certs/files/\${client}.p12 \${client}/\${client}-\${uid}.p12
docker cp \${takcontainer}:/opt/tak/certs/files/takserver.p12 \${client}/takserver-\${uid}.p12

# Compress the data package and remove temporary files
zip client-data-pkgs/\${client} \${client}/*
rm -r \${client}
echo "Created client-data-pkgs/\${client}.zip"
EOF
chmod a+x mk-client-dp.sh

# Update system and reboot
sudo apt upgrade -y
sudo apt autoremove -y

echo "Updated system, rebooting!"
sudo reboot
