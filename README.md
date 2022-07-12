# TAK Server Docker Helper

Simple scripts to set up a fresh Raspbian 64-bit or Ubuntu Server 64-bit install with TAK Server. The server will generate certs if you want to use TLS. The script `./mk-client-cert.sh` can be used to generate a client certificate. `reload-certs.sh` will restart the TAK Server and reload certs.

This is intended to help you spin up a simple TAK Server install on a Raspberry Pi, for anything more extensive you should refer to the server manual.

To use:

- Do a fresh Raspbian 64-bit install
- Copy the TAK Server docker zip to the user's home directory
- Copy all the script and config files in this repo to the user's home directory
- Edit the `helper-script.conf` file and update any values you need to
- Run `0-system-setup.sh` to install Docker, update the system, and extract the TAK Server, your computer will reboot after this is done
- Run `1-build-and-run-containers.sh` to build and run the TAK Server and DB containers. The TAK Server will start up whenever your Pi starts up.

If you want to wipe the server and start fresh, delete and re-create the `tak-db` folder.

Certs are in `tak/certs/files`
