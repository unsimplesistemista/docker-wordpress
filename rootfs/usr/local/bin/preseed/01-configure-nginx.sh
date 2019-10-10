#!/bin/bash

if [ ${CACHE_ENABLED} -eq 1 ]; then
  SKIP_CACHE=0
else
  SKIP_CACHE=1
fi
perl -p -i -e "s/#SKIP_CACHE#/${SKIP_CACHE}/g" /etc/nginx/sites-available/*
perl -p -i -e "s/#CACHE_200_MINUTES#/${CACHE_200_MINUTES}/g" /etc/nginx/sites-available/*

# Make it possible to run wordpress sites in subfolders ...
for wordpress_subfolder in ${WORDPRESS_SUBFOLDERS}; do
  wordpress_subfolder=`echo ${wordpress_subfolder} | sed "s/\/$//g" | sed "s/$/\//g"`
  wordpress_subfolder_scaped=`echo ${wordpress_subfolder} | sed "s/\//\\\\\\\\\//g"`
  echo "=> Enabling Wordpress subfolder ${wordpress_subfolder} ..."
  perl -p -i -e "s/#WORDPRESS_SUBFOLDERS_HERE#/#WORDPRESS_SUBFOLDERS_HERE#\n\n    location ${wordpress_subfolder_scaped} {\n        try_files \\\$uri \\\$uri\/ ${wordpress_subfolder_scaped}index.php\\\$is_args\\\$args;\n    }/g" /etc/nginx/sites-available/*
done
perl -p -i -e "s/#WORDPRESS_SUBFOLDERS_HERE#//g" /etc/nginx/sites-available/*
