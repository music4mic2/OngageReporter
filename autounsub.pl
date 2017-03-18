#!/opt/msys/3rdParty/bin/perl

##############################################################
# AUTOUNSUB.PL
# This script was written to provide a way to capture bounce records
# and provide direct action on them in the Ongage environment

# Tom Mairs - 10 Jul 2014
# Last Mod - 11 Dec 2014 - Tom Mairs
#
##############################################################


# Before using, CPAN Install DBI, DBD::ODBC, Proc::PID::File

# Add this line to a cron file in /etc/cron.d:
#   */30 * * * * root /opt/msys/3rdParty/bin/perl /opt/msys/ecelerity/etc/conf/default/autounsub.pl >/dev/null 2>&1
# This will restart the unsub process every 30 minutes if it has stopped

use strict;
use warnings;
use Fcntl qw(:flock);
use JLog::Reader;
use LWP::UserAgent;
use HTTP::Request::Common;
use JSON; 
use Config::Tiny;

# Check to make sure the script is not already running
unless (flock(DATA, LOCK_EX|LOCK_NB)) {
    print "$0 is already running. Exiting.\n";
    exit(1);
}

# Custom Permfail Log format: "%t@ %i@ %r@ %R@ %m@ %M@ %g@ %b@ %c@ %C@ %vctx_mess{mo_campaign_id} %B@ %H@"
my $PATH = "/var/log/ecelerity/permfail_log1";     # the location of the log file to consume
my $SUB = "master";
my $r = JLog::Reader->new($PATH);
my $reclog    = "/var/log/ecelerity/unsub.log";  # the location to record removal actions
my $addrlog    = "/var/log/ecelerity/addr.log";  # emails with soft bounces
my %addr_data = ();
my $isHardBounce = "false";
my $isSoftBounce = "false";
my $hblist = "/var/log/ecelerity/hblist-";
my $sblist = "/var/log/ecelerity/sblist-";
my $logline = "";
my $logstr = "";
my $CampaignID ="";
my $CampaignID_c ="";
my $ListID=0;

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


# Load the addrs table if it exists
if (open (ADDRFILE, "<", $addrlog)){;
    while(my $line = <ADDRFILE>){
        chomp $line;
        my @fields = split "," , $line;
        $addr_data{ $fields[0] } = $fields[1];
    }
    close(ADDRFILE);
}

# Open the Jlog file for reading
#$r->add_subscriber($SUB);
$r->open($SUB);

# Start continuous loop
while(1){
    while(my $line = $r->read) {
      $hblist = "/var/log/ecelerity/hblist-";
      $sblist = "/var/log/ecelerity/sblist-";
        # Split the log line into parts at the '@' delimeter
        # so we can extract the email address and bounce code
        my @fields = split('@', $line, 14);

       # Added by Tom Mairs 10DEC2014 to deal with metrics update problem
       $CampaignID = $fields[10];
       $CampaignID_c = $CampaignID;
       $CampaignID_c =~ s/\s//g;
       $ListID = $fields[11];
       if (!$ListID){
         $ListID = 7420; #When Ongage starts sending this in the headers, it will have the right value
       }

        # Check to make sure the line is a relevant code (10,20,22,23,60,90) bounce line then handle it
        if ($fields[9] eq '10') {

# Added by Tom Mairs 10DEC2014 to deal with metrics update problem
$isHardBounce = "true";
#print "+H\r\n";

            # Call OnGage API here
            my $json = "{\"change_to\":\"unsubscribe\", \"emails\": [ \"$fields[2]\@$fields[3]\" ]}";
            my $ua = LWP::UserAgent->new;
            my $req = POST 'https://api.ongage.net/api/contacts/remove';
            $req->header( 'Content-Type' => 'application/json' );
            $req->header( 'X_USERNAME' => ''. $user_name .'' );
            $req->header( 'X_PASSWORD' => ''. $password .'' );
            $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
            $req->content( $json );
            my $res = $ua->request($req);

            my $mytimestamp = time();
            my $logstr = "".$mytimestamp." Removing an invalid email address: ".$fields[2]."\@".$fields[3]."\r\n";
            # open the recordlog to catch unsubscribed events
            open (RECFILE, ">>", $reclog) or die $!;
            print RECFILE $logstr;
            close(RECFILE);
            $r->checkpoint();
        }
        elsif ($fields[9] eq '90') {

# Added by Tom Mairs 10DEC2014 to deal with metrics update problem
$isHardBounce = "true";
#print "+H\r\n";

            # Call OnGage API here
            my $json = "{\"change_to\":\"unsubscribe\", \"emails\": [ \"$fields[2]\@$fields[3]\" ]}";
            my $ua = LWP::UserAgent->new;
            my $req = POST 'https://api.ongage.net/api/contacts/remove';
            $req->header( 'Content-Type' => 'application/json' );
            $req->header( 'X_USERNAME' => ''. $user_name .'' );
            $req->header( 'X_PASSWORD' => ''. $password .'' );
            $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
            $req->content( $json );
            my $res = $ua->request($req);

            my $mytimestamp = time();
            my $logstr = "".$mytimestamp." Processing unsubscribe for email address: ".$fields[2]."\@".$fields[3]."\r\n";
            # open the recordlog to catch unsubscribed events
            open (RECFILE, ">>", $reclog) or die $!;
            print RECFILE $logstr;
            close(RECFILE);
            $r->checkpoint();
        }

        elsif (($fields[9] eq '1') || ($fields[9] eq '21') || ($fields[9] eq '24') || ($fields[9] eq '25') || ($fields[9] eq '30') || ($fields[9] eq '40') || ($fields[9] eq '50') || ($fields[9] eq '51') || ($fields[9] eq '52') || ($fields[9] eq '53') || ($fields[9] eq '54') || ($fields[9] eq '70')) {
            $r->checkpoint();
            my $vemail = "".$fields[2]."\@".$fields[3]."";

# Added by Tom Mairs 10DEC2014 to deal with metrics update probl
$isSoftBounce = "true";
#print "+S\r\n";

        }
        elsif (($fields[9] eq '20') || ($fields[9] eq '22') || ($fields[9] eq '23') || ($fields[9] eq '60')) {
            $r->checkpoint();
            my $vemail = "".$fields[2]."\@".$fields[3]."";
            if (exists $addr_data{ $vemail }){
                $addr_data{ $vemail }++;
                open (ADDRFILE, ">", $addrlog) or die $!;
                while ( my ($key, $value) = each(%addr_data) ) {
                    print ADDRFILE "$key,$key => $value\n";
                }
                close(ADDRFILE);
            }
            else{
                open (ADDRFILE, ">>", $addrlog) or die $!;
                print ADDRFILE $vemail .",1";
                close(ADDRFILE);
            }
# Added by Tom Mairs 10DEC2014 to deal with metrics update probl
$isSoftBounce = "true";
#print "+S\r\n";

            if ($addr_data{ $vemail } > 3){

# Added by Tom Mairs 10DEC2014 to deal with metrics update problem
$isHardBounce = "true";
#print "+H\r\n";

                # Call OnGage API here
                my $json = "{\"change_to\":\"unsubscribe\", \"emails\": [ \"$fields[2]\@$fields[3]\" ]}";
                my $ua = LWP::UserAgent->new;
                my $req = POST 'https://api.ongage.net/api/contacts/remove';
                $req->header( 'Content-Type' => 'application/json' );
                $req->header( 'X_USERNAME' => ''. $user_name .'' );
                $req->header( 'X_PASSWORD' => ''. $password .'' );
                $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
                $req->content( $json );
                my $res = $ua->request($req);
 
                my $mytimestamp = time();
                my $logstr = "".$mytimestamp." Processing 4count_unsubscribe for email address: ".$fields[2]."\@".$fields[3]."\r\n";
                # open the recordlog to catch unsubscribed events
                open (RECFILE, ">>", $reclog) or die $!;
                print RECFILE $logstr;
                close(RECFILE);
            }
        }
        else {
            # Skip the line
            $r->checkpoint();
        }
  if ($isHardBounce eq "true"){
    $hblist .= $ListID . "-" . $CampaignID_c;
    if (not -e $hblist) {
      $logline = '{"list_id":7420,"mailing_id":"'.$CampaignID.'" ,"change_to":"bounce","emails": [';
      open (RECFILE, ">>", $hblist) or die $!;
        print RECFILE $logline;
      close(RECFILE);
    }
    $logline = "\"".$fields[2]."\@".$fields[3]."\",";
    open (RECFILE, ">>", $hblist) or die $!;
      print RECFILE $logline;
    close(RECFILE);
    $isHardBounce = "false";
  }
  if ($isSoftBounce eq "true"){
    $sblist .= $ListID . "-" . $CampaignID_c;
    if (not -e $sblist) {
      $logline = '{"list_id":'.$ListID.',"mailing_id":"'.$CampaignID.'" ,"change_to":"soft_bounce","emails": [';
      open (RECFILE, ">>", $sblist) or die $!;
        print RECFILE $logline;
      close(RECFILE);
    }
    $logline = "\"".$fields[2]."\@".$fields[3]."\",";
    open (RECFILE, ">>", $sblist) or die $!;
      print RECFILE $logline;
    close(RECFILE);
    $isSoftBounce = "false";
  }
    }
    
    # Sleep after reading all data
    sleep(1);
}
$r->close();

### DO NOT REMOVE THE FOLLOWING LINES ###

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!


