## check_azure_mdb

Check if An Azure MariaDB or a Mysql is up, get a metric or check the earliestRestoreDate 

### prerequisites

This script uses theses libs : REST::Client, Data::Dumper, DateTime, Getopt::Long, JSON, Monitoring::Plugin

to install them type :

```
sudo cpan  REST::Client Data::Dumper Encode  Getopt::Long JSON DateTime File::Basename Readonly Getopt::Long Monitoring::Plugin
```
### use case

```bash
check_azure_mdb.pl 3.0.0

This nagios plugin is free software, and comes with ABSOLUTELY NO WARRANTY.
It may be used, redistributed and/or modified under the terms of the GNU
General Public Licence (see http://www.fsf.org/licensing/licenses/gpl.txt).

check_azure_mdb.pl is a Nagios check that uses Azure s REST API to get azure MariaDB or MySql state and metrics

Usage: check_azure_mdb.pl  [-v] -T <TENANTID> -I <CLIENTID> -s <SUBID> -p <CLIENTSECRET> [-m <METRICNAME> -i <INTERVAL>]|[-e ] [-r <RESOURCETYPE>] -H <HOSTNAME> -d <dbtype> [-w <WARNING> -c <CRITICAL>] [-z]

 -?, --usage
   Print usage information
 -h, --help
   Print detailed help screen
 -V, --version
   Print version information
 --extra-opts=[section][@file]
   Read options from an ini file. See https://www.monitoring-plugins.org/doc/extra-opts.html
   for usage and examples.
 -T, --tenant=STRING
 The GUID of the tenant to be checked
 -I, --clientid=STRING
 The GUID of the registered application
 -p, --clientsecret=STRING
 Access Key of registered application
 -s, --subscriptionid=STRING
 Subscription GUID
 -e, --earliestRestoreDate
 Flag to check earliestRestoreDate. when used --metrics is ignored
 -m, --metric=STRING
 METRIC=cpu_percent | io_consumption_percent | connection_failed |  storage_percent | active_connections | memory_percent | serverlog_storage_percent | network_bytes_egress | network_bytes_ingress
 -i, --time_interval=STRING
 TIME INTERVAL use with metric PT1M|PT5M|PT15M|PT30M|PT1H|PT6H|PT12H|P1D
 -H, --Host=STRING
Host name
 -r, --resource_type=STRING
resource type (Default: "servers"). Can be "servers", "flexibleServers".
 -d, --dbtype=STRING
dbtype=MariaDB | MySql
 -w, --warning=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -c, --critical=threshold
   See https://www.monitoring-plugins.org/doc/guidelines.html#THRESHOLDFORMAT for the threshold format.
 -z, --zeroed
 disable unknown status when receive empty data for a metric
 -t, --timeout=INTEGER
   Seconds before plugin times out (default: 30)
 -v, --verbose
   Show details for command-line debugging (can repeat up to 3 times)

```

sample to get cpu usage:

```bash
check_azure_mdb.pl --tenant=<TENANTID> --clientid=<CLIENTID> --subscriptionid=<SUBID> --clientsecret=<CLIENTSECRET> --Host=MyHost --dbtype=MariaDB --metric=cpu_percent --time_interval=PT5M --warning=80 --critical=90
```

you may get  :

```bash
  OK - CPU percent = 0.11% | cpu_percent=0.11%;80;90
```

sample to check if BDD is running

```bash
check_azure_mdb.pl --tenant=<TENANTID> --clientid=<CLIENTID> --subscriptionid=<SUBID> --clientsecret=<CLIENTSECRET> --Host=MyHost --dbtype=MySql
```
you may get :

```bash
OK database server : MyHost type : MySql status is Ready
```

