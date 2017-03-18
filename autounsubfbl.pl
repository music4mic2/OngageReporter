#!/opt/msys/3rdParty/bin/perl

##############################################################
# AUTOUNSUBFBL.PL
# This script was written to provide a way to capture FBL records
# and provide direct action on them in the Ongage environment

# Tom Mairs - 10 Jul 2014
# Last Mod - 11 Dec 2014 - Tom Mairs
#
##############################################################


# Add this line to a cron file in /etc/cron.d:
#   */30 * * * * root /opt/msys/3rdParty/bin/perl /opt/msys/ecelerity/etc/conf/default/autounsubfbl.pl >/dev/null 2>&1
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

my $PATH = "/var/log/ecelerity/fbllog.jlog";     # the location of the log file to consume
my $SUB = "master";
my $r = JLog::Reader->new($PATH);
my $reclog    = "/var/log/ecelerity/unsub.log";  # the location to record removal actions

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

# Open the Jlog file for reading
$r->add_subscriber($SUB);
$r->open($SUB);

# Start continuous loop
while(1){
    while(my $line = $r->read) {
        # Split the log line into parts at the '@' delimeter
        # so we can extract the email address and bounce code
        # FBL Log looks like this: 1224699438@18/00-02937-E2E6FF84@F@someone@test.com@default@default@abuse@yahoo.com@true
        # All lines need to be consumed
        my @fields = split('@', $line, 10);
        
        # Call OnGage API here
        my $json = "{\"change_to\":\"unsubscribe\", \"emails\": [ \"$fields[3]\@$fields[4]\" ]}";
        my $ua = LWP::UserAgent->new;
        my $req = POST 'https://api.ongage.net/api/contacts/remove';
        $req->header( 'Content-Type' => 'application/json' );
        $req->header( 'X_USERNAME' => ''. $user_name .'' );
        $req->header( 'X_PASSWORD' => ''. $password .'' );
        $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
        $req->content( $json );
        my $res = $ua->request($req);

# Added by Tom Mairs 10DEC2014 to deal with metrics update problem
 #Call Ongage API to update complaint count here
        # Call OnGage API here
        $json = "{\"change_to\":\"complaint\", \"emails\": [ \"$fields[3]\@$fields[4]\" ]}";
        $ua = LWP::UserAgent->new;
        $req = POST 'https://api.ongage.net/api/contacts/remove';
        $req->header( 'Content-Type' => 'application/json' );
        $req->header( 'X_USERNAME' => ''. $user_name .'' );
        $req->header( 'X_PASSWORD' => ''. $password .'' );
        $req->header( 'X_ACCOUNT_CODE' => ''. $account .'' );
        $req->content( $json );
        $res = $ua->request($req);

            
        my $mytimestamp = time();
        my $logstr = "".$mytimestamp." Removing an FBL reported address: ".$fields[3]."\@".$fields[4]."\r\n";
        # open the recordlog to catch unsubscribed events
        open (RECFILE, ">>", $reclog) or die $!;
        print RECFILE $logstr;
        close(RECFILE);
        $r->checkpoint();
    }
    
    # Sleep after reading all data
    sleep(1);
}


### DO NOT REMOVE THE FOLLOWING LINES ###

__DATA__
This exists to allow the locking code at the beginning of the file to work.
DO NOT REMOVE THESE LINES!


