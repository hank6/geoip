#!/bin/sh

wget https://github.com/hank6/GeoLite2xtables/archive/master.zip
unzip master.zip

cd GeoLite2xtables-master
./00_download_geolite2
./10_download_countryinfo

cat /tmp/GeoLite2-Country-Blocks-IPv{4,6}.csv | ./20_convert_geolite2 /tmp/CountryInfo.txt > xtables-addons-2.14/geoip/GeoIP-legacy.csv

mkdir -p /usr/share/xt_geoip
./xtables-addons-2.14/geoip/xt_geoip_build -D /usr/share/xt_geoip/ xtables-addons-2.14/geoip/GeoIP-legacy.csv
modprobe xt_geoip
opt=$?

cd ..
rm -rf GeoLite2xtables-master master.zip

if [ $opt -eq 0 ] ; then
    echo -e "\nUpdata success!"
else
    echo -e "\nUpdata fiald!"
fi
