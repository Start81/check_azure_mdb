#!/usr/bin/perl -w
#===============================================================================
# Script Name   : check_azure_mdb.pl
# Usage Syntax  : check_azuresql.pl [-v] -T <TENANTID> -I <CLIENTID> -s <SUBID> -p <CLIENTSECRET> [-m <METRICNAME> -i <INTERVAL>]|[-b ] [-r <RESOURCETYPE>]
#                                   -H <SERVERNAME> -d <dbtype> [-w <WARNING>] [-c <CRITICAL>] [-z]
# Author        : Start81
# Version       : 3.0.0
# Last Modified : 20/09/2023
# Modified By   : Start81
# Description   : Check Azure MySql/MariaDb
# Depends On    : REST::Client, Data::Dumper, DateTime, Json,Monitoring::Plugin, File::Basename, Readonly
#
# Changelog:
#    Legend:
#       [*] Informational, [!] Bugix, [+] Added, [-] Removed
#
# - 17/04/2023 | 1.0.0 | [*] initial realease
# - 18/04/2023 | 1.0.1 | [*] Add network_bytes_egress and network_bytes_ingress
# - 22/05/2023 | 1.1.0 | [+] Add zeroed flag
# - 22/05/2023 | 1.1.1 | [*] Rename perfdata and update  threshold compare with earliestRestoreDate
# - 06/07/2023 | 1.2.1 | [*] Add [-r <RESOURCETYPE>] 
# - 17/08/2023 | 2.0.0 | [+] Now the script can only check if the db is running  
# - 17/08/2023 | 2.0.1 | [+] Add unit in return message 
# - 25/08/2023 | 2.1.0 | [*] now the script check db health only when no metrics name is provided
# - 20/09/2023 | 3.0.0 | [*] implement Monitoring::Plugin lib
#===============================================================================
use REST::Client;
use Data::Dumper;
use JSON;
use utf8;
use DateTime;
use File::Basename;
use strict;
use warnings;
use Readonly;
use Monitoring::Plugin;
Readonly our $VERSION => '3.0.0';

my $o_verb;
sub verb { my $t=shift; print $t,"\n" if ($o_verb) ; return 0}
my $me = basename($0);
my $np = Monitoring::Plugin->new(
    usage => "Usage: %s  [-v] -T <TENANTID> -I <CLIENTID> -s <SUBID> -p <CLIENTSECRET> [-m <METRICNAME> -i <INTERVAL>]|[-e ] [-r <RESOURCETYPE>] -H <HOSTNAME> -d <dbtype> [-w <WARNING> -c <CRITICAL>] [-z]",
    plugin => $me,
    shortname => " ",
    blurb => "$me is a Nagios check that uses Azure s REST API to get azure MariaDB or MySql state and metrics",
    version => $VERSION,
    timeout => 30
);

my %db_type = ('MariaDB' => ['Microsoft.DBforMariaDB', '2018-06-01'],
    'MySql' => ['Microsoft.DBforMySQL', '2017-12-01']);
my %metrics = ('cpu_percent' => ['%', 'average'],
    'io_consumption_percent' => ['%', 'average'],
    'connections_failed' => ['', 'total'],
    'storage_percent' => ['%', 'average'],
    'active_connections' => ['', 'average'],
    'memory_percent' => ['%', 'average'],
    'serverlog_storage_percent'=> ['%', 'average'],
    'network_bytes_egress'=> ['B', 'total'],
    'network_bytes_ingress'=> ['B', 'total'],
);

my %interval = ('PT1M' => '1',
    'PT5M' => '5',
    'PT15M' => '15',
    'PT30M' => '30',
    'PT1H' => '60',
    'PT6H' => '360',
    'PT12H' => '720',
    'P1D' => '1440');


#write content in a file
sub write_file {
    my ($content,$tmp_file_name) = @_;
    my $fd;
    verb("write $tmp_file_name");
    if (open($fd, '>', $tmp_file_name)) {
        print $fd $content;
        close($fd);       
    } else {
        my $msg ="unable to write file $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    
    return 0
}

#Read previous token  
sub read_token_file {
    my ($tmp_file_name) = @_;
    my $fd;
    my $token ="";
    verb("read $tmp_file_name");
    if (open($fd, '<', $tmp_file_name)) {
        while (my $row = <$fd>) {
            chomp $row;
            $token=$token . $row;
        }
        close($fd);
    } else {
        my $msg ="unable to read $tmp_file_name";
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return $token
    
}

#get a new acces token
sub get_access_token{
    my ($clientid,$clientsecret,$tenantid) = @_;
    verb(" tenantid = " . $tenantid);
    verb(" clientid = " . $clientid);
    verb(" clientsecret = " . $clientsecret);
    #Get token
    my $client = REST::Client->new();
    my $payload = 'grant_type=client_credentials&client_id=' . $clientid . '&client_secret=' . $clientsecret . '&resource=https%3A//management.azure.com/';
    my $url = "https://login.microsoftonline.com/" . $tenantid . "/oauth2/token";
    $client->POST($url,$payload);
    if ($client->responseCode() ne '200') {
        my $msg = "UNKNOWN response code : " . $client->responseCode() . " Message : Error when getting token" . $client->{_res}->decoded_content;
        $np->plugin_exit('UNKNOWN',$msg);
    }
    return $client->{_res}->decoded_content;
}
$np->add_arg(
    spec => 'tenant|T=s',
    help => "-T, --tenant=STRING\n"
          . ' The GUID of the tenant to be checked',
    required => 1
);
$np->add_arg(
    spec => 'clientid|I=s',
    help => "-I, --clientid=STRING\n"
          . ' The GUID of the registered application',
    required => 1
);
$np->add_arg(
    spec => 'clientsecret|p=s',
    help => "-p, --clientsecret=STRING\n"
          . ' Access Key of registered application',
    required => 1
);
$np->add_arg(
    spec => 'subscriptionid|s=s',
    help => "-s, --subscriptionid=STRING\n"
          . ' Subscription GUID ',
    required => 1
);
$np->add_arg(
    spec => 'earliestRestoreDate|e',
    help => "-e, --earliestRestoreDate\n"  
         . ' Flag to check earliestRestoreDate. when used --metrics is ignored',
    required => 0
);
$np->add_arg(
    spec => 'metric|m=s',
    help => "-m, --metric=STRING\n"  
         . ' METRIC=cpu_percent | io_consumption_percent | connection_failed |  storage_percent | active_connections | memory_percent | serverlog_storage_percent | network_bytes_egress | network_bytes_ingress',
    required => 0
);
$np->add_arg(
    spec => 'time_interval|i=s',
    help => "-i, --time_interval=STRING\n"  
         . ' TIME INTERVAL use with metric PT1M | PT5M | PT15M | PT30M | PT1H | PT6H | PT12H | P1D ',
    required => 0
);
$np->add_arg(
    spec => 'Host|H=s', 
    help => "-H, --Host=STRING\n"  
         . 'Host name',
    required => 1
);

$np->add_arg(
    spec => 'resource_type|r=s', 
    help => "-r, --resource_type=STRING\n"  
         . 'resource type (Default: "servers"). Can be "servers", "flexibleServers".',
    required => 1,
    default => "servers"
);
$np->add_arg(
    spec => 'dbtype|d=s', 
    help => "-d, --dbtype=STRING\n"  
         . 'dbtype=MariaDB | MySql',
    required => 1
);
$np->add_arg(
    spec => 'warning|w=s',
    help => "-w, --warning=threshold\n" 
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'critical|c=s',
    help => "-c, --critical=threshold\n"  
          . '   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.',
);
$np->add_arg(
    spec => 'zeroed|z',
    help => "-z, --zeroed\n"  
         . ' disable unknown status when receive empty data for a metric',
    required => 0
);


$np->getopts;
my $subid = $np->opts->subscriptionid;
my $tenantid = $np->opts->tenant;
my $clientid = $np->opts->clientid;
my $clientsecret = $np->opts->clientsecret; 
my $o_warning = $np->opts->warning;
my $o_critical = $np->opts->critical;
my $o_server_name = $np->opts->Host;
my $o_metric = $np->opts->metric;
my $o_earliestRestoreDate;
$o_earliestRestoreDate = $np->opts->earliestRestoreDate if (defined $np->opts->earliestRestoreDate);
my $o_time_interval = $np->opts->time_interval;
my $o_timeout = $np->opts->timeout;
my $o_ressource_type = $np->opts->resource_type;
my $result;
$o_verb = $np->opts->verbose if (defined $np->opts->verbose);
my $o_db_type =$np->opts->dbtype ;
my $o_zeroed = $np->opts->zeroed  if (defined $np->opts->zeroed);

if (!defined($o_earliestRestoreDate))  {
    if (defined($o_metric)) {
        if (!exists $metrics{$o_metric}) {
            my @keys = keys %metrics;
            $np->plugin_die("Metric " . $o_metric . " name not defined available metrics are " . join(', ', @keys) ." \n");
        }
        if (defined($o_time_interval)) {
            if (!exists $interval{$o_time_interval}) {
                my @keys = keys %interval;
                $np->plugin_die("Time interval " . $o_time_interval . " not defined available interval are " . join(', ', @keys) ."\n");
            }
        } else {
            $np->plugin_die("Time interval missing\n");
        }
    } 

}
if (!exists $db_type{$o_db_type}){
     $np->plugin_die( "availaible db type are  MariaDB | MySql \n");
}
if ($o_timeout > 60){
    $np->plugin_die("Invalid time-out");
}
my @criticals = ();
my @warnings = ();
my @ok = ();
my $i = 0;
my $j = 0;
my $server_found = 0;
$np->getopts;
my $resource_group_name;
my $msg = "";
my $reponse_server;
my $server_name;
my $server_state;
my @server_list;
my $status;

verb(" subid = " . $subid);
verb(" tenantid = " . $tenantid);
verb(" clientid = " . $clientid);
verb(" clientsecret = " . $clientsecret);
#Get token
my $tmp_file = "/tmp/$clientid.tmp";
my $token;
my $token_json;
if (-e $tmp_file) {
    #Read previous token
    $token = read_token_file ($tmp_file);
    $token_json = from_json($token);
    #check token expiration
    my $expiration = $token_json->{'expires_on'} - 60;
    my $current_time = time();
    if ($current_time > $expiration ) {
        #get a new token
        $token = get_access_token($clientid,$clientsecret,$tenantid);
        write_file($token,$tmp_file);
        $token_json = from_json($token);
    }
} else {
    $token = get_access_token($clientid,$clientsecret,$tenantid);
    write_file($token,$tmp_file);
    $token_json = from_json($token);;
}
verb(Dumper($token_json ));
$token = $token_json->{'access_token'};
verb("Authorization :" . $token);
#Get resourcegroups list
my $client = REST::Client->new();
$client->addHeader('Authorization', 'Bearer ' . $token);
$client->addHeader('Content-Type', 'application/json;charset=utf8');
$client->addHeader('Accept', 'application/json');

#verb(Dumper($response_json));

my $url = "https://management.azure.com/subscriptions/" . $subid . "/resourcegroups?api-version=2020-06-01";
$client->GET($url);
if($client->responseCode() ne '200') {
    $msg = "response code : " . $client->responseCode() . " Message : Error when getting resource groups list" . $client->responseContent();
    $np->plugin_exit('UNKNOWN',$msg);
}
my $response_json = from_json($client->responseContent());
do {
        $resource_group_name = $response_json->{'value'}->[$i]->{"name"};
        verb("\ngetting server list from resourceGroups :" . $resource_group_name);
        my $get_serveurlist_url = "https://management.azure.com/subscriptions/" . $subid . "/resourceGroups/" . $resource_group_name;
        $get_serveurlist_url = $get_serveurlist_url . "/providers/". $db_type{$o_db_type}->[0] ."/$o_ressource_type?api-version=" . $db_type{$o_db_type}->[1] ;
        verb($get_serveurlist_url);
        $client->GET($get_serveurlist_url);

        if($client->responseCode() ne '200') {
            $msg = "response code : " . $client->responseCode() . " Message : Error when getting serveur list " . $client->responseContent();
            $np->plugin_exit('UNKNOWN',$msg);
        }
        $reponse_server = from_json($client->responseContent());
        verb(Dumper($reponse_server));
        $j = 0;
        $server_found=0;
        while ((($server_found==0)) and (exists $reponse_server->{'value'}->[$j])) {
            $server_name = $reponse_server->{'value'}->[$j]->{'name'};
            if ($server_name eq $o_server_name) {
                $server_found = 1;
                if (defined($o_earliestRestoreDate)) {
                    my $dt_now = DateTime->now;
                    my $backup_date = $reponse_server->{'value'}->[$j]->{"properties"}->{'earliestRestoreDate'};
                    verb('earliestRestoreDate ' . $backup_date);

                    my @temp = split('T', $backup_date);
                    $backup_date = $temp[0];
                    my $backup_time = $temp[1];
                    @temp = split('-', $backup_date);
                    my @temp_time = split(':', $backup_time);
                    my $dt = DateTime->new(
                        year       => $temp[0],
                        month      => $temp[1],
                        day        => $temp[2],
                        hour       => $temp_time[0],
                        minute     => $temp_time[1],
                        second     => 0,
                        time_zone  => 'UTC',
                    );
                    $result = $dt_now->delta_days($dt)->in_units('days');
                    verb("earliestRestoreDate : " . $result);
                    $msg = "earliestRestoreDate is " . $result . " day ago ";
                    $np->add_perfdata(label => "earliestRestoreDate", value => $result, warning => $o_warning, critical => $o_critical);
                    if ((defined($o_warning) || defined($o_critical))) {
                        $np->set_thresholds(warning => $o_warning, critical => $o_critical);
                        $status = $np->check_threshold($result);
                        push( @criticals, $msg) if ($status==2);
                        push( @warnings, $msg) if ($status==1);
                        push (@ok,$msg) if ($status==0);
                    } else {
                        push (@ok,$msg);
                    }
                } else {  
                    #Getting metric
                    if ($o_metric){
                        my $now = DateTime->now;
                        $now->set_time_zone("UTC");
                        my $begin = $now->clone;
                        $begin = $begin->subtract(minutes => $interval{$o_time_interval});
                        my $date_now_str = $now->ymd("-") . "T" . $now->hms('%3A') . "Z";
                        my $date_begin_str = $begin->ymd("-") . "T" . $begin->hms('%3A') . "Z";
                        my $get_metric_url = "https://management.azure.com/subscriptions/" . $subid . "/resourcegroups/" . $resource_group_name;
                        $get_metric_url = $get_metric_url . "/providers/".$db_type{$o_db_type}->[0]."/$o_ressource_type/" . $server_name ;
                        #$get_metric_url = $get_metric_url ."/providers/microsoft.insights/metricDefinitions?api-version=2018-06-01-preview";
                        $get_metric_url = $get_metric_url . "/providers/microsoft.insights/metrics?api-version=2018-01-01&timespan=" . $date_begin_str;
                        $get_metric_url = $get_metric_url . "%2F" . $date_now_str . "&interval=" . $o_time_interval . "&metricnames=" . $o_metric;
                        verb($get_metric_url);
                        $client->GET($get_metric_url);
                        if($client->responseCode() ne '200') {
                            $msg = "response code : " . $client->responseCode() . " Message : Error when getting metric " . $client->responseContent();
                            $np->plugin_exit('UNKNOWN',$msg);
                        }
                        my $reponse_metrics = from_json($client->responseContent());
                        verb(Dumper($reponse_metrics));
                        #Check if desired data exist
                        if (!exists $reponse_metrics->{'value'}->[0]->{'timeseries'}->[0]->{'data'}->[0]->{$metrics{$o_metric}->[1]}) {
                            if (defined $o_zeroed){
                                $result = 0
                            } else {
                                $msg =  "metric " . $o_metric . " unavailable or empty data " . Dumper($reponse_metrics);
                                $np->plugin_exit('UNKNOWN',$msg);
                            } 
                        } else {
                            $result = $reponse_metrics->{'value'}->[0]->{'timeseries'}->[0]->{'data'}->[0]->{$metrics{$o_metric}->[1]};
                        }
                        
                        $msg = $reponse_metrics->{'value'}->[0]->{'name'}->{'localizedValue'} . " = " . sprintf("%.2f",$result) . $metrics{$o_metric}->[0];
                        $np->add_perfdata(label => $o_metric  , value => sprintf("%.2f",$result), uom => $metrics{$o_metric}->[0], warning => $o_warning, critical => $o_critical);
                        if ((defined($o_warning) || defined($o_critical))) {
                            $np->set_thresholds(warning => $o_warning, critical => $o_critical);
                            $status = $np->check_threshold($result);
                            push( @criticals, $msg) if ($status==2);
                            push( @warnings, $msg) if ($status==1);
                            push (@ok,$msg) if ($status==0);
                        } else {
                            push (@ok,$msg);
                        }
                    #End Getting metric
                    } else {
                        #check db server state
                        $server_state = $reponse_server->{'value'}->[$j]->{'properties'}->{'userVisibleState'}; #OK Ready
                        $msg = "database server : $o_server_name type : $o_db_type status is $server_state";
                        if ($server_state ne "Ready") {
                            push( @criticals, $msg)
                        } else {
                            push (@ok,$msg);
                        }
                    }
                
                }
            } else {
                push(@server_list, $server_name);
            }
            $j++;
        }
        $i++;
}  while (($server_found==0) and (exists $response_json->{'value'}->[$i]));

if ($server_found  == 0) {
    $msg = "server " . $o_server_name . " not found. Available server(s) are : " . join(", ", @server_list);
    $np->plugin_exit('UNKNOWN',$msg);
}
$np->plugin_exit('CRITICAL', join(', ', @criticals)) if (scalar @criticals > 0);
$np->plugin_exit('WARNING', join(', ', @warnings)) if (scalar @warnings > 0);
$np->plugin_exit('OK',join(', ', @ok ));
