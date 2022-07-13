# TAK Server Docker Helper

Simple scripts to set up a fresh Raspbian 64-bit or Ubuntu Server 64-bit install with TAK Server. The server will generate certs if you want to use TLS.

This is intended to help you spin up a simple TAK Server install on a Raspberry Pi, for anything more extensive you should refer to the server manual.

To use:

- Do a fresh Raspbian 64-bit install
- Copy the TAK Server docker zip to the user's home directory
- Copy all the script and config files in this repo to the user's home directory
- Edit the `helper-script.conf` file and update any values you need to
- Run `0-system-setup.sh` to install Docker, update the system, and extract the TAK Server, your computer will reboot after this is done
- Run `1-build-and-run-containers.sh` to build and run the TAK Server and DB containers. The TAK Server will start up whenever your Pi starts up.

If you want to wipe the server and start fresh, delete and re-create the `tak-db` folder.

Some useful scripts are created in the unzipped TAK Server folder:

| script  | description  |
|---|---|
| `mk-client-cert.sh` | Creates a client certificate in `tak/certs/files`, the `.p12` file is the one you need for your device |
| `reload-cert.sh` | Restart the TAK Server and load any new certs |
| `create-http-user.sh` | Creates a user/password for accessing the HTTP server on port `8080` |
| `add-webadmin-role-to-cert.sh` | Adds the admin role to an existing cert, allowing the cert holder to connect to the HTTPS server on port `8443` |

Certs are in `tak/certs/files`

Why not give me a bunch of money? [![](https://www.paypalobjects.com/en_US/i/btn/btn_donate_LG.gif)](https://www.paypal.com/paypalme/paypaulmandal)
