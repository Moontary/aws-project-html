#!/bin/bash
  yum -y update
  yum -y install httpd
  echo "<h2>Hello webserver ${webserver}</h2><br>Build by Terraform!"  >  /var/www/html/index.html
  sudo service httpd start
  chkconfig httpd on

