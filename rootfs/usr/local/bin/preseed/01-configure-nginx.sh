#!/bin/bash

if [ ${CACHE_ENABLED} -eq 1 ]; then
  SKIP_CACHE=0
else
  SKIP_CACHE=1
fi
perl -p -i -e "s/#SKIP_CACHE#/${SKIP_CACHE}/g" /etc/nginx/sites-enabled/*
perl -p -i -e "s/#CACHE_200_MINUTES#/${CACHE_200_MINUTES}/g" /etc/nginx/sites-enabled/*
