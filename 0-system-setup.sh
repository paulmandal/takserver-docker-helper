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

# fix TAKServer Docker for Postgres 14.4
sed -i "s/FROM postgres:.*/FROM postgres:14.4/" docker/Dockerfile.takserver-db
sed -i "s/postgresql-10-postgis-2.4/postgresql-14-postgis-3/" docker/Dockerfile.takserver-db
sed -i "s/RUN echo/#RUN echo/" docker/Dockerfile.takserver-db
sed -i $'s/^\tapt update/RUN apt update/' docker/Dockerfile.takserver-db
sed -i "s/-t stretch-backports//" docker/Dockerfile.takserver-db
sed -i "s#postgresql/10/#postgresql/14/#g" tak/db-utils/configureInDocker.sh

# create some useful scripts
echo '#!/bin/bash' > mk-client-cert.sh && echo 'docker exec -it takserver-${takServerVersion} bash -c "cd /opt/tak/certs && ./makeCert.sh client $1"' >> mk-client-cert.sh && chmod a+x mk-client-cert.sh
echo '#!/bin/bash' > reload-certs.sh && echo 'docker exec -d takserver-${takServerVersion} bash -c "cd /opt/tak/ && ./configureInDocker.sh"' >> reload-certs.sh && chmod a+x reload-certs.sh

# Update system and reboot
sudo apt upgrade -y
sudo apt autoremove -y

echo "Updated system, rebooting!"
sudo reboot
