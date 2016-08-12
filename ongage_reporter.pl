#!/opt/msys/3rdParty/bin/perl -w

##############################################################
# ONGAGE_REPORTER.PL
# This script was written to provide a way to extrat reporting
# from the Ongage environment and store locally for later
# 3rd party reporting

# Tom Mairs - 10 Jul 2014
# Last Mod - 17 Oct 2014 16:00 MST - Tom Mairs
#
##############################################################

# Add this line to a cron file in /etc/cron.d:
#   0 1 * * * root /opt/msys/3rdParty/bin/perl /opt/msys/ecelerity/etc/conf/default/ongage_reporter.pl >/dev/null 2>&1
# This will fire the script daily at the approriate time

use strict;
use warnings;
use Fcntl qw(:flock);
use LWP::UserAgent;
use File::Copy;
use File::Path;
use HTTP::Request::Common;
use Time::Local;
use Data::Dumper;
use JSON;
use Config::Tiny;

# Check to make sure the script is not already running
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
    print "$0 is already running. Exiting.\n";
    exit(1);
}

# Get the actual UTC time
my @t = localtime(time);
my $gmt_offset = timegm(@t) - timelocal(@t);
my $utc_time = time - $gmt_offset;

my ($sec, $min, $hour, $mday, $mon, $year,$wday,$yday,$isdst) = localtime($utc_time);
my $yesterday_midday=timelocal(0,0,12,$mday,$mon,$year) - 24*60*60;
($sec, $min, $hour, $mday, $mon, $year) = localtime($yesterday_midday);
$year = $year+1900;
$mon++;
my $yesterday = sprintf("%04d-%02d-%02d", $year, $mon, $mday);

($sec, $min, $hour, $mday, $mon, $year,$wday,$yday,$isdst) = localtime($utc_time);
my $lastmonth_midday=timelocal(0,0,12,$mday,$mon,$year) - 30*24*60*60;
($sec, $min, $hour, $mday, $mon, $year) = localtime($lastmonth_midday);
$year = $year+1900;
$mon++;
my $lastmonth = sprintf("%04d-%02d-%02d", $year, $mon, $mday);

($sec,$min,$hour,$mday,$mon,$year,$wday,$yday,$isdst) = localtime($utc_time);
$year = $year+1900;
$mon++;
my $today = sprintf("%04d-%02d-%02d", $year, $mon, $mday);

($sec, $min, $hour, $mday, $mon, $year,$wday,$yday,$isdst) = localtime($utc_time);
$year = $year+1900;
$mon++;
my $utcday = sprintf("%04d-%02d-%02d", $year, $mon, $mday);


# Collect and validate command line arguments
my $x=0;
my @parms;
my $i=0;
my $cid=0;
my $altfilepath="";
my $altrange="";
my $altdate="";
my $altcampaign=0;
my $reportdir = "";
my $altdebug = "false";

print "\n";

foreach (@ARGV) {
    $parms[$x] = $_;
    $x++;
}

while ($i<$x){
    if ($parms[$i] eq "--debug"){
        $altdebug = "true";
    }
    if ($parms[$i] eq "-L"){
        $i++;
        $altfilepath = $parms[$i];
    }
    if ($parms[$i] eq "-R"){
        $i++;
        $altrange = $parms[$i];
    }
    if ($parms[$i] eq "-D"){
        $i++;
        $altdate = $parms[$i];
    }
    if ($parms[$i] eq "-C"){
        $i++;
        $altcampaign = $parms[$i];
    }
    if (($parms[$i] eq "-h")||($parms[$i] eq "--help")){
        print "USAGE: perl ongage_reporter.pl [--debug] [-h|--help] [-L filepath] [-R YYYY-MM-DD] [-C 1234567] [-D YYYY-MM-DD]\n";
        print "  --debug - Display enhanced diagnostic messages in the output \n";
        print "  -h or --help  - Display this help message \n";
        print "  -L (location) is a file path that can be ./ or /var/log/ or whatever. \n";
        print "     This defaults to the Momentum reports directory /var/log/ecelerity/reports \n";
        print "  -R (range) is how far back to check mailings for activity.\n";
        print "     By default, the report will evaluate any mailings send in the past 30 days. \n";
        print "  -D (date) is the day you want to see engagement and summary information for.\n";
        print "     By default this is 'YESTERDAY' and compensates for UTC reported activity. \n";
        print "  -C (campaign) - If this is a valid campaign ID format, all activity for the \n";
        print "     campaign in the date range will be reported. \n";
        print "  If arguments do not validate, the defaults will be use and an warning will be displayed. \n";
        exit(0);
    }
    $i++;
}


# set the base location to save reports
if (-d $altfilepath) {
    $reportdir = $altfilepath;
}
else {
    $reportdir = "/var/log/ecelerity/reports";
}

print "dir : $reportdir \n";
mkpath($reportdir); 

# validate date fields
$altrange =~ s/\s+$//;
$altrange =~ s/^\s*//;
($year, $mon, $mday) = split ('-', $altrange);
eval{timelocal(0,0,0,$mday, $mon, $year)};
if ($@) {
   print "$@ \n";
   print "Invalid search range selected \n";
   $altrange = $lastmonth;
}

$altdate =~ s/\s+$//;
$altdate =~ s/^\s*//;
($year, $mon, $mday) = split ('-', $altdate);
eval{timelocal(0,0,0,$mday, $mon, $year)};
if ($@) {
   print "$@ \n";
   print "Invalid report date selected \n";
   $altdate = $yesterday;
}

# validate Campaign ID field
if ($altcampaign =~ m/^\d*$/){
    $cid = $altcampaign;
}
else {
    $cid = 0;
}

# DEBUG
if ($altdebug eq "true"){
    print "Report date = $altdate \r\n";
    print "Search range = $altrange \r\n";
    print "Campaign = $cid \r\n";
    print "Report Dir = $reportdir \r\n";
    print "LAST MONTH = $lastmonth \n";
    print "YESTERDAY = $yesterday \n";
    print "TODAY = $today \n";
    print "UTC DATE = $utcday \n";
}

my $summarylog   = "$reportdir/summary_";  # the base location to save daily reports
my $engagelog    = "$reportdir/engage_";  # the base location to save daily reports
my $campaignlog  = "$reportdir/campaign_$cid";  # the base location to save daily reports
my $cfg_fn = "";

if (-e "/opt/msys/ecelerity/etc/conf/default/") {
  $cfg_fn = '/opt/msys/ecelerity/etc/conf/default/ongage.ini';
}
else{
  $cfg_fn = './ongage.ini';
}
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


########################################
# Generate the Summary Report
########################################
# Call Ongage API here

print "Generating summary report \r\n";

my $cidsearch = "";
if ($cid != 0){
    $cidsearch = ', [ "mailing_id", "=", "'.$cid.'" ]';
}
my $json = <<JSON;
{
    "select": [
    "mailing_name",
    [ "MAX(`delivery_timestamp`)",
    "delivery_timestamp" ],
    "sum(`sent`)",
    "sum(`hard_bounces`)",
    "sum(`soft_bounces`)",
    "sum(`failed`)",
    [ "(sum(`failed`) DIV sum(`sent`))",
    "bounce_rate" ],
    "sum(`success`)",
    "sum(`unique_opens`)",
    [ "(sum(`unique_opens`) DIV sum(`sent`))",
    "unique_open_rate" ],
    "sum(`unique_clicks`)",
    [ "(sum(`unique_clicks`) DIV sum(`sent`))",
    "unique_click_rate" ],
    "sum(`unsubscribes`)",
    "sum(`complaints`)",
    "list_id"
    ],
    "from": "mailing",
    "group": [
    "list_id",
    "mailing_id"
    ],
    "order": [
    [ "mailing_name", "asc" ]
    ],
    "filter":[
    [ "delivery_date", "=", "$altdate" ] $cidsearch
    ]
}
JSON

my $num_bytes = length($json);
my $ua = LWP::UserAgent->new;
my $req = POST 'https://api.ongage.net/api/reports/query';
$req->header( 'Content-Type' => 'application/json' );
$req->header( 'Content-Length' => "$num_bytes" );
$req->header( 'X_USERNAME' => "$user_name" );
$req->header( 'X_PASSWORD' => "$password" );
$req->header( 'X_ACCOUNT_CODE' => "$account" );
$req->content( $json );
my $res = $ua->request($req);

$summarylog = $summarylog . $altdate . ".log";
my $logstr = $res->content;

if ($altdebug eq "true"){
    print "Raw summary output: \n $logstr \n";
}

# open the recordlog to catch unsubscribed events
open (RFILE, ">", $summarylog);
print RFILE $logstr;
close(RFILE);

########################################
# Generate the Engagement Report
########################################
# Call Ongage API here

print "Generating engagement report \r\n";

my $json1 = <<JSON;
{
    "select": [
    "mailing_id",
    "mailing_name"
    ],
    "filter": [
    [ "delivery_date", ">", "$altrange" ] $cidsearch
    ],
    "from": "mailing",
    "group": [
    "list_id",
    "mailing_id"
    ]
}
JSON

print("json1: " . $json1 . "\n") if $altdebug eq "true";

$res="";
$num_bytes = length($json1);
$ua = LWP::UserAgent->new;
$req = POST "https://api.ongage.net/api/reports/query";
$req->header( 'Content-Type' => 'application/json' );
$req->header( 'Content-Length' => "$num_bytes" );
$req->header( 'X_USERNAME' => "$user_name" );
$req->header( 'X_PASSWORD' => "$password" );
$req->header( 'X_ACCOUNT_CODE' => "$account" );
$req->content( $json1 );
$res = $ua->request($req);

+unless($res->is_success) {
+  if($altdebug eq "true") {
+    print "X_USERNAME => $user_name\n";
+    print "X_PASSWORD => $password\n";
+    print "X_ACCOUNT_CODE => $account\n";
+  }
+  die $res->status_line;
+}
+

# collect all mailingIDs
+print("DEBUG: " . $res->content . "\n") if $altdebug eq "true";
my $j_decoded = decode_json($res->content);
my $midlist = "";
my @mailings = @{ $j_decoded->{'payload'} };

my $lastmid = "";
foreach my $f ( @mailings ) {
    if ($f->{"mailing_id"} ne $lastmid){
        #    print $f->{"mailing_id"} . "\n";
        $midlist .= $f->{"mailing_id"} . ", ";
        $lastmid = $f->{"mailing_id"};
    }
}
$midlist = substr($midlist, 0, -2);

if ($altdebug eq "true"){
    print "Raw list of mailing IDs output: \n $midlist \n";
}

# collect all listIDs
#my $j_decoded = decode_json($res->content);
my $lidlist = "";
my @lists = @{ $j_decoded->{'payload'} };

my $lastlid = "";
my @reportID = ();
foreach my $f ( @lists ) {
    if ($f->{"list_id"} ne $lastlid){
        #    print $f->{"list_id"} . "\n";
        $lidlist .= $f->{"list_id"} . ", ";
        $lastlid = $f->{"list_id"};

        # All lists must be checked separately, 
        #  so need to call this in a loop over
        #  all the list_id's reported above

        my $json2 = <<JSON;
        {
          "list_id": "$lastlid",
          "name": "engagement",
          "date_format": "mm/dd/yyyy",
          "file_format": "csv",
          "mailing_id": [ $midlist ],
          "type": "behavior",
          "fields_selected": [
          "contact_ID",
          "IP_Instance",
          "last_OS",
          "last_Browser",
          "email",
          "list_source",
          "first_name",
          "last_name",
          "asset"
          ]
        }
JSON

        $res="";
        $num_bytes = length($json2);
        $ua = LWP::UserAgent->new;
        $req = POST 'https://api.ongage.net/api/segments/export';
        $req->header( 'Content-Type' => 'application/json' );
        $req->header( 'Content-Length' => "$num_bytes" );
        $req->header( 'X_USERNAME' => "$user_name" );
        $req->header( 'X_PASSWORD' => "$password" );
        $req->header( 'X_ACCOUNT_CODE' => "$account" );
        $req->content( $json2 );
        $res = $ua->request($req);

        #collect the report ID from this to use below
        $j_decoded = decode_json($res->content);

        push @reportID,$j_decoded->{'payload'}{'id'}; 
        my $reportID_current = $j_decoded->{'payload'}{'id'};
        if ($reportID_current){
          print "reportID: $reportID_current \r\n";
        }
    }
}
$lidlist = substr($lidlist, 0, -2);

if ($altdebug eq "true"){
    print "Raw list of list IDs output: \n $lidlist \n";
}


$engagelog = $engagelog . $altdate . ".csv";
if (-e $engagelog) {
  move($engagelog, $engagelog.".bak");
}

# flag to make sure we only add one header row per report file
my $headeraddedflag = "false";

if (@reportID) {
  foreach my $f ( @reportID ) {
  if ($f){  
    my $loopcount = 1;
    $res="";
    do{

        if ($altdebug eq "true"){
          print "Collecting data from report ID $f \n";
        }

        $ua = LWP::UserAgent->new;
        $req = HTTP::Request->new(GET => 'https://connect.ongage.net/api/segments/'. $f .'/export_retrieve');
        $req->header( 'Content-Type' => 'application/zip' );
        $req->header( 'X_USERNAME' => "$user_name" );
        $req->header( 'X_PASSWORD' => "$password" );
        $req->header( 'X_ACCOUNT_CODE' => "$account" );
        
        $res = $ua->request($req);
        
        # if response contains "Precondition Failed" then
        # retry in 30 seconds
        if ($res->code eq "412") {
            my $j_decoded = decode_json($res->content);
            #   print "JSON: " . Dumper($j_decoded) ."\r\n";
            print "waiting for 60 seconds - try # ". $loopcount  ." \r\n";
            sleep(60);
        }
        $loopcount++;
        
    } while (($res->code eq 412)&&($loopcount < 21));
    
    if ($loopcount < 20 ){
        open F, ">ereport.zip" or die "$! ereport.zip";
        binmode F;
        print F $res->content;
        close F;
        
        system("/usr/bin/unzip ereport.zip");

        opendir D, './' or die "Could not open dir: $!\n";
        my @filelist = grep(/^export\.behavior.*\.csv/i, readdir D);
        my $behaviorlog = $filelist[0];
        
        opendir D, './' or die "Could not open dir: $!\n";
        my @filelist2 = grep(/^engagement.export.*\.csv/i, readdir D);
        $logstr = "";
        
        open (FILE, "<", $behaviorlog);
        while(my $line = <FILE>){
            chomp $line;
            if ($altdebug eq "true"){
                print "$line \n";
            }
            my @fields = split "," , $line;

            if (($fields[6] eq "timestamp")&&($headeraddedflag eq "false")){
                $headeraddedflag = "true";
                $logstr .= $line . "\r\n";
            }
            if (substr($fields[6],1,10) eq $altdate){
                $logstr .= $line . "\r\n";
            }
        }
        
        close(FILE);
        
        open (FILE, ">>", $engagelog);
        print FILE $logstr;
        close(FILE);
        unlink "./ereport.zip";
        unlink @filelist;
        unlink @filelist2;
    }
    else{
        print "file not generated :(";
    }
   }
  }
}
else{
    print "There is nothing to report for the requested day \r\n";
}



### DO NOT REMOVE THE FOLLOWING LINES ###

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!

