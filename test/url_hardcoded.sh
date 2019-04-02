#!/usr/bin/env bash
# ./url_hardcoded.sh 2>&1

egrep http *sh */*sh \
  --exclude autodc*sh --exclude hooks*sh --exclude stage_citrixhow* \
  --exclude vmdisk2image-pc.sh --exclude global.vars.sh \
| grep -v -i \
  -e localhost -e 127.0.0.1 -e _HOST -e _http_ \
  -e download.nutanix.com -e portal.nutanix.com -e python -e github -e '#'
