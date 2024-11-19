#!/bin/bash

# Bash shell script for generating self-signed certs. Run this in a folder, as it
# generates a few files. Large portions of this script were taken from the
# following artcile:
# 
# http://usrportage.de/archives/919-Batch-generating-SSL-certificates.html
# 
# Additional alterations by: Brad Landers
# Date: 2012-01-27
# usage: ./gen_cert.sh example.com

# Script accepts a single argument, the fqdn for the cert
DOMAIN="$1"
if [ -z "$DOMAIN" ]; then
  echo "Usage: $(basename $0) <domain>"
  exit 11
fi

fail_if_error() {
  [ $1 != 0 ] && {
    unset PASSPHRASE
    exit 10
  }
}

# Check to see if a cert/key pair already exists
if [[ -f "/etc/ssl/certs/cert.pem" ]]; then
  echo "Self signed certs are already present. Good day to you."
  exit
fi

# Generate a passphrase
export PASSPHRASE=$(head -c 500 /dev/urandom | tr -dc a-z0-9A-Z | head -c 128; echo)

# Certificate details; replace items in angle brackets with your own info
subj="
C=GB
ST=OR
O=Blah
localityName=London
commonName=$DOMAIN
organizationalUnitName=CoSector
emailAddress=admin@example.com
"

# Generate the server private key
/usr/bin/openssl genrsa -des3 -out cert.key -passout env:PASSPHRASE 2048
fail_if_error $?

# Generate the CSR
/usr/bin/openssl req \
    -new \
    -batch \
    -subj "$(echo -n "$subj" | tr "\n" "/")" \
    -key cert.key \
    -out cert.csr \
    -passin env:PASSPHRASE
fail_if_error $?
cp cert.key cert.key.org
fail_if_error $?

# Strip the password so we don't have to type it every time we restart Apache
/usr/bin/openssl rsa -in cert.key.org -out cert.key -passin env:PASSPHRASE
fail_if_error $?

# Generate the cert (good for 10 years)

/usr/bin/openssl x509 -req -days 3650 -in cert.csr -signkey cert.key -out cert.crt
fail_if_error $?

# Check to see if the dirs exist on persistent volume and make them
[ ! -d "/etc/ssl/certs" ] && mkdir -p /etc/ssl/certs
[ ! -d "/etc/ssl/private" ] && mkdir -p /etc/ssl/private

# Move to volume
mv cert.crt /etc/ssl/certs/
mv cert.csr /etc/ssl/certs/
mv cert.key /etc/ssl/private/
cat /etc/ssl/private/cert.key /etc/ssl/certs/cert.crt  > /etc/ssl/certs/cert.pem
chmod 0600 /etc/ssl/private/cert.key
