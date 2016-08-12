# OngageReporter
This is a specific utility for reporting on Ongage activity 

NOTE: This script assumes you are using Message Systems Momentum version 3.6 or newer and you have a config file with your Ongage credentials here: /opt/msys/ecelerity/etc/conf/default/ongage.ini


================================================
Using Ongage reporter on a non-Momentum Linux server

You must be sudo or root user:
  sudo -s

You should also make sure you have all the latest updates first:
  yum update -y

Then also do these:

yum install perl cpan wget make gcc openssl-devel unzip -y
cpan Bundle::LWP File::Copy Time::Local Data::Dumper JSON HTTP::Request Fcntl Config::Tiny File::Path
copy ongage_reporter.pl to home dir
copy engage.ini to home dir
modify ongage.ini with your Ongage credentials:
  username=user
  password=pass
  account=acc

execute the script:
  perl ongage_reporter.pl 

================================================
USAGE: perl ongage_reporter.pl [--debug] [-h|--help] [-L filepath] [-R YYYY-MM-DD] [-C 1234567] [-D YYYY-MM-DD]
  --debug - Display enhanced diagnostic messages in the output 
  -h or --help  - Display this help message 
  -L (location) is a file path that can be ./ or /var/log/ or whatever. 
     This defaults to the Momentum reports directory /var/log/ecelerity/reports 
  -R (range) is how far back to check mailings for activity.
     By default, the report will evaluate any mailings send in the past 30 days. 
  -D (date) is the day you want to see engagement and summary information for.
     By default this is 'YESTERDAY' and compensates for UTC reported activity. 
  -C (campaign) - If this is a valid campaign ID format, all activity for the 
     campaign in the date range will be reported. 
  If arguments do not validate, the defaults will be use and an warning will be displayed. 


Note that all the options above are completley optional.  If a report date (-D) or a search range (-R) are ommitted, an informational message will be posted indicating that the date is out of range and the default setting will be used as described in the usage information above.

