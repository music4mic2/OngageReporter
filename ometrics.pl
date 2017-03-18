#!/opt/msys/3rdParty/bin/perl

##############################################################
# OMETRICS.PL
# This script was written to capture delivery and bouce data 
# and provide direct updates in the Ongage environment using their API

# Tom Mairs - 08 Dec 2014
# Last Mod - 11 Dec 2014 - Tom Mairs
#
##############################################################


# Before using, CPAN Install DBI, DBD::ODBC, Proc::PID::File

# Add this line to a cron file in /etc/cron.d:
#   */10 * * * * root /opt/msys/3rdParty/bin/perl /opt/msys/ecelerity/etc/conf/default/ometrics.pl >/dev/null 2>&1
# This will restart the unsub process every 30 minutes if it has stopped

use strict;
use warnings;
use Fcntl qw(:flock);
use JLog::Reader;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON; 
use Config::Tiny;
use Data::Dumper;
use File::Path;
use File::Copy;

# Check to make sure the script is not already running
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
    print "$0 is already running. Exiting.\n";
    exit(1);
}

my $hblist = "/var/log/ecelerity/hblist-";
my $sblist = "/var/log/ecelerity/sblist-";
#my $hblist    = "/var/log/ecelerity/hblist.json";
#my $sblist    = "/var/log/ecelerity/sblist.json";
my $hbjson="";
my $sbjson="";
my $res="";
my $req="";
my $ua="";
my $tag = "";
my $f="";
my @filelist=();
my $ftmp = "";

my $cfg_fn = '/opt/msys/ecelerity/etc/conf/default/ongage.ini';
if (not -e $cfg_fn) {
  printf STDERR "ERROR: config file doesn't exist (%s)\n", $cfg_fn;
  exit(1);
} elsif (not -r $cfg_fn) {
  printf STDERR "ERROR: can't read config file (%s)\n", $cfg_fn;
  exit(1);
}

my $cfg = Config::Tiny->read($cfg_fn);
if (not $cfg) {
  printf STDERR "ERROR: couldn't read config file [%s]: %s\n", $cfg_fn, $cfg->errstr();
  exit(1);
}

# Parameters for the Ongage API requests
my $user_name = $cfg->{_}{username};
my $password = $cfg->{_}{password};
my $account = $cfg->{_}{account};

while(1){

# loop through all bounce files
  opendir(D, '/var/log/ecelerity/') or die "Could not open dir: $!\n";
  @filelist = grep { /sblist-.*/ } readdir(D);
  closedir(D);

  foreach $f (@filelist){
print "reading from $f \r\n";
    $ftmp = $f . ".tmp";
    move("/var/log/ecelerity/".$f,"/var/log/ecelerity/".$ftmp);
    if (open (FILE, "<", "/var/log/ecelerity/".$ftmp)){
      $hbjson = <FILE>;
      $tag = chop($hbjson);
      if ($tag ne ","){
        chop($hbjson);
      }
      $hbjson .= "]}";
      close(FILE);
      unlink "/var/log/ecelerity/".$ftmp;
    }


    if ($hbjson){
      # Call OnGage API here
      $ua = LWP::UserAgent->new;
      $req = POST 'https://api.ongage.net/api/contacts/remove';
      $req->header( 'Content-Type' => 'application/json' );
      $req->header( 'X_USERNAME' => ''. $user_name .'' );
      $req->header( 'X_PASSWORD' => ''. $password .'' );
      $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
      $req->content( $hbjson );
      $res = $ua->request($req);
my $rv =  decode_json($res->content);
#print Dumper($rv);
    }
  }


  opendir(D, '/var/log/ecelerity/') or die "Could not open dir: $!\n";
  @filelist = grep { /hblist-.*/ } readdir(D);
  closedir(D);
  foreach $f (@filelist){
print "reading from $f \r\n";
    $ftmp = $f . ".tmp";
    move("/var/log/ecelerity/".$f,"/var/log/ecelerity/".$ftmp);
    if (open (FILE, "<", "/var/log/ecelerity/".$ftmp)){
      $hbjson = <FILE>;
      $tag = chop($hbjson);
      if ($tag ne ","){
        chop($hbjson);
      }
      $hbjson .= "]}";
      close(FILE);
      unlink "/var/log/ecelerity/".$ftmp;
    }
print "Calling API for hard bounces \r\n";

    if ($hbjson){
      # Call OnGage API here
      $ua = LWP::UserAgent->new;
      $req = POST 'https://api.ongage.net/api/contacts/remove';
      $req->header( 'Content-Type' => 'application/json' );
      $req->header( 'X_USERNAME' => ''. $user_name .'' );
      $req->header( 'X_PASSWORD' => ''. $password .'' );
      $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
      $req->content( $hbjson );
      $res = $ua->request($req);
my $rv =  decode_json($res->content);
#print Dumper($rv);
    }
  }
sleep(60)
}

### DO NOT REMOVE THE FOLLOWING LINES ###

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!


