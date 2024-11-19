#!/bin/bash

############
# lighttpd #
############

# put server name in apache conf
sed -i "s/#IIP_SERVER_NAME#/$IIP_SERVER_NAME/g" /etc/lighttpd/lighttpd.conf
sed -i "s/#IIP_SERVER_NAME#/$IIP_SERVER_NAME/g" /etc/lighttpd/lighttpd_ssl.conf

mkdir -p /var/www/acme-docroot/

# For now $USE_SS_CERT will control whether or not to use a self-signed certificate or get one from letsencrypt
# letsenrypt won't work with IPs, or with domainnames without dots in then (eg localhost) or from behind a firewall even if we give the NSG the acme :@ (!!)
if [ $USE_SS_CERT ]; then
  echo -e "-- ${bold}Making self-signed certificates for local container ($IIP_SERVER_NAME)${normal} --"
  /bin/gen_cert.sh $IIP_SERVER_NAME
  if [ -f /etc/ssl/certs/$IIP_SERVER_NAME.crt ]; then
    printf "%-50s $print_ok\n" "Certificates generated"
  else
    printf "%-50s $print_fail\n" "Certificates Could not be generated ($?)"
  fi
else
  echo -e "-- ${bold}Obtaining certificates from letsencrypt using certbot ($IIP_SERVER_NAME)${normal} --"
  staging=""
  ## Maybe we want staging certs for dev instances? but they will use a FAKE CA and not really allow us to test stuff properly
  ## Perhaps when letsencrypt start issuing certs for IPs we should modify the above so that --staging is used with certbot when HOSTNAME_IS_IP?
  [[ $ENVIRONMENT == "dev" ]] && staging="--staging"

  # Correct cert on data volume in /data/pki/certs? We should be able to just bring apache up with ssl
  # If not...
  if [ ! -f /etc/ssl/certs/$IIP_SERVER_NAME.crt ]; then
    # Lets encrypt has a cert but for some reason this has not been copied to where apache wants them
    if [ -f /etc/letsencrypt/live/base/fullchain.pem ]; then
      echo -e "Linking existing cert/key to /etc/ssl" 
      #ln -s /etc/letsencrypt/live/base/fullchain.pem /etc/ssl/certs/$IIP_SERVER_NAME.pem
      cat /etc/letsencrypt/live/base/privkey.pem /etc/letsencrypt/live/base/fullchain.pem > /etc/ssl/certs/$IIP_SERVER_NAME.pem
      sed -i '/^$/d' /etc/ssl/certs/$IIP_SERVER_NAME.pem
    else
      # No cert here, We'll register and get one and store all the gubbins on the letsecnrypt volume (n.b. this needs to be an azuredisk for symlink reasons)
      # Need a webserver running to get cert...
      /usr/sbin/lighttpd -f /etc/lighttpd/lighttpd.conf

      echo -e "Getting new cert and linking cert/key to /etc/ssl"
      mkdir -p /var/www/acme-docroot/.well-known/acme-challenge
      certbot -n certonly --webroot $staging -w /var/www/acme-docroot/ --expand --agree-tos --email $ADMIN_EMAIL --cert-name base -d $IIP_SERVER_NAME
      # In case these are somehow hanging around to wreck the symlinking
      [ -f  /etc/ssl/certs/$IIP_SERVER_NAME.pem ] && rm /etc/ssl/certs/$IIP_SERVER_NAME.pem

      # Link cert and key to a location that our general apache config will know about
      if [ -f /etc/letsencrypt/live/base/fullchain.pem ]; then
        cat /etc/letsencrypt/live/base/privkey.pem /etc/letsencrypt/live/base/fullchain.pem > /etc/ssl/certs/$IIP_SERVER_NAME.pem
        sed -i '/^$/d' /etc/ssl/certs/$IIP_SERVER_NAME.pem
      else
        echo -e "${red}${bold}Certificate could not be obtained from letsencrypt using certbot!${normal}"
      fi

      echo "Stopping lighttpd on just :80"
      # turns out lighttpd is awkward to stop
      kill $(ps aux | grep '/usr/sbin/lighttpd' | awk '{print $2}')
    fi
    printf "%-50s $print_ok\n" "Certificate obtained"; # hmmm... catch an error maybe?
  else
     printf "%-50s $print_ok\n" "Certificate already in place";
  fi
  echo -e "-- ${bold}Setting up auto renewal${normal} --"
  # Remove this one as it is no good to us in this context
  rm /etc/cron.d/certbot
  # Add some evaluated variables 
  sed -i "s/#IIP_SERVER_NAME#/$IIP_SERVER_NAME/g" /var/tmp/renew_cert
  sed -i "s/#ADMIN_EMAIL#/$ADMIN_EMAIL/" /var/tmp/renew_cert
  # copy renew_script into cron.monthly (whould be frequent enough)
  mkdir -p /etc/cron.weekly
  mv /var/tmp/renew_cert /etc/cron.weekly/renew_cert
  chmod ug+x /etc/cron.weekly/renew_cert
  service cron start
  printf "%-50s $print_ok\n" "renew_cert script moved to /etc/cron.weekly";
fi


#############
# START IIP #
#############

echo "--------- Starting IIP ---------"
LIGHTTPD_START=`/usr/sbin/lighttpd -D -f /etc/lighttpd/lighttpd_ssl.conf`
if [ "$?" -ne "0" ]; then
  echo "### There was an issue starting IIP/lighttpd. We have kept this container alive for you to go and see what's up ###"
  tail -f /dev/null
fi
