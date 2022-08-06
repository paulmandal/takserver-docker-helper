#!/bin/bash
if [ $# -eq 0 ]; then
    printf "Usage: ${0} <client>"
    exit
else
    # Check for missing requirements
    missingreq=0
    for req in printf tr uuidgen zip docker
    do
        if [ -z $(which ${req}) ]; then
            printf "This script requires ${req}.  Please install it first.\n"
            ((missingreq++))
        fi
    done
    if [ $missingreq -gt 0 ]; then
        exit
    fi
    client=$1
    
    # Load variables from config file
    if [ -f client-dp.conf ]; then
        printf "Loading configuration file.\n"
        . client-dp.conf
    else
        printf "Configuration file not found.  Creating a new one.\n"
    fi
    
    # Check that all configuration variables loaded successfully
    if [ -z "${servername}" ]; then
        printf "Enter a server name to be displayed in TAK clients. (Default is TAK Server)\n"
        read servername
        if [ -z "${servername}" ]; then
            servername="TAK Server"
        fi
        printf "servername=\"${servername}\"\n" >> client-dp.conf
    fi
    if [ -z "${serveraddress}" ]; then
        printf "Enter the server's hostname or IP address.  This must be accessible to TAK clients. (Default is $(hostname))\n"
        read serveraddress
        if [ -z "${serveraddress}" ]; then
            serveraddress=$(hostname)
        fi
        printf "serveraddress=\"${serveraddress}\"\n" >> client-dp.conf
    fi
    if [ -z "${serverport}" ]; then
        printf "Enter the SSL port number.  (Default is 8089)\n"
        read serverport
        if [ -z "${serverport}" ]; then
            serverport="8089"
        fi
        printf "serverport=\"${serverport}\"\n" >> client-dp.conf
    fi
    if [ -z "${takcontainer}" ]; then
        printf "Enter the name of the TAK Server's docker container. (Default is takserver-4.6)\n"
        read takcontainer
        if [ -z "${takcontainer}" ]; then
            serverport="takserver-4.6"
        fi
        printf "takcontainer=\"${takcontainer}\"\n" >> client-dp.conf
    fi

    # If client name includes spaces, replace them with dashes
    tr ' ' '-' <<<"$client"
    uid=$(uuidgen)
    dpname=$(printf "${servername}-DP" | tr ' ' '-')
    mkdir $client
    
    #Stop if target directory exists
    if [ $? -ne 0 ]; then
      printf "Error creating directory.  Do you already have a directory called ${client}?\nThe script will now stop to avoid data loss.\n"
      exit
    fi
    
    # Create the client certs in the TAK container
    docker exec -it ${takcontainer} bash -c "cd /opt/tak/certs && ./makeCert.sh client ${client}"
    
    # Create the data package manifest file
    printf "<MissionPackageManifest version=\"2\">\n" > ${client}/manifest.xml
    printf "  <Configuration>\n" >> ${client}/manifest.xml
    printf "    <Parameter name=\"uid\" value=\"${uid}\"/>\n" >> ${client}/manifest.xml
    printf "    <Parameter name=\"name\" value=\"${dpname}\"/>\n" >> ${client}/manifest.xml
    printf "    <Parameter name=\"onReceiveDelete\" value=\"true\"/>\n" >> ${client}/manifest.xml
    printf "  </Configuration>\n" >> ${client}/manifest.xml
    printf "  <Contents>\n" >> ${client}/manifest.xml
    printf "    <Content ignore=\"false\" zipEntry=\"certs/preference.pref\"/>\n" >> ${client}/manifest.xml
    printf "    <Content ignore=\"false\" zipEntry=\"certs/takserver-${uid}.p12\"/>\n" >> ${client}/manifest.xml
    printf "    <Content ignore=\"false\" zipEntry=\"certs/${client}-${uid}.p12\"/>\n" >> ${client}/manifest.xml
    printf "  </Contents>\n" >> ${client}/manifest.xml
    printf "</MissionPackageManifest>\n" >> ${client}/manifest.xml
    
    # Create the pref file
    printf "<?xml version='1.0' encoding='ASCII' standalone='yes'?>\n" > ${client}/preference.pref
    printf "<preferences>\n" >> ${client}/preference.pref
    printf "  <preference version=\"1\" name=\"cot_streams\">\n" >> ${client}/preference.pref
    printf "    <entry key=\"count\" class=\"class java.lang.Integer\">1</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"description0\" class=\"class java.lang.String\">${servername}</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"enabled0\" class=\"class java.lang.Boolean\">true</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"connectString0\" class=\"class java.lang.String\">${serveraddress}:${serverport}:ssl</entry>\n" >> ${client}/preference.pref
    printf "  </preference>\n" >> ${client}/preference.pref
    printf "  <preference version=\"1\" name=\"com.atakmap.app_preferences\">\n" >> ${client}/preference.pref
    printf "    <entry key=\"displayServerConnectionWidget\" class=\"class java.lang.Boolean\">true</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"caLocation\" class=\"class java.lang.String\">cert/takserver-${uid}.p12</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"caPassword\" class=\"class java.lang.String\">atakatak</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"clientPassword\" class=\"class java.lang.String\">atakatak</entry>\n" >> ${client}/preference.pref
    printf "    <entry key=\"certificateLocation\" class=\"class java.lang.String\">cert/${client}-${uid}.p12</entry>\n" >> ${client}/preference.pref
    printf "  </preference>\n" >> ${client}/preference.pref
    printf "</preferences>\n" >> ${client}/preference.pref
    
    # Copy the truststore and client certs - append a unique ID to avoid filename collisions
    docker cp ${takcontainer}:/opt/tak/certs/files/${client}.p12 ${client}/${client}-${uid}.p12
    docker cp ${takcontainer}:/opt/tak/certs/files/takserver.p12 ${client}/takserver-${uid}.p12
    
    # Compress the data package and remove temporary files
    zip ${client} ${client}/*
    rm -r ${client}
fi
