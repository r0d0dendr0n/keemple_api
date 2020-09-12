#!/usr/bin/perl -CA

# ./KeempleScrapper.pl ~/.keempleAPI.conf 'głośniki salon' 1 1
# ./KeempleScrapper.pl ~/.keempleAPI.conf 'światło salon' 2 1

# dbus-send --session --print-reply --dest="KeempleAPI.ScrapperDBusService" /KeempleAPI/ScrapperService KeempleAPI.ScrapperDBusService.performAction string:'Światło salon' int32:2 int32:1

#Error while executing command: no such element: Unable to locate element: /html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input at /usr/share/perl5/site_perl/Selenium/Remote/Driver.pm line 403.
# at /usr/share/perl5/site_perl/Selenium/Remote/Driver.pm line 353.
# at /usr/share/perl5/site_perl/Selenium/Remote/Finders.pm line 26.
#Unable to find device search field. Probably login failed.

use Config::INI::Reader;
use Getopt::Std;
use Net::DBus::Reactor;
use Text::Trim;

use KeempleAPI::SeleniumScrapper;
use KeempleAPI::ScrapperDBusService;

use utf8;
no warnings 'utf8';

our $VERSION = '0.3';

our %options = ();
Getopt::Std::getopts('bc:d:fghi:ks:m', \%options);

sub VERSION_MESSAGE {
	print "KeempleScrapper $VERSION\n";
	print "Tomasz Rozynek <Tomasz.Rozynek@dir.pl> ©2020\n\n";
}

sub HELP_MESSAGE {
	print "Usage: KeempleScrapper.pl [-m] [-y] [-c \"config path\"] -d \"device name\" [-i switchIdx] -s targetState\n";
	print "\n";
	print "Options:\n";
	print "  -b	Start DBus daemon.\n";
	print "  -c	Configuration file path. Default is \"~/.keempleAPI.conf\".\n";
	print "  -d	Device full display name.\n";
	print "  -f	Fork - daemon mode.\n";
	print "  -g	Debug mode.\n";
	print "  -h	Help message.\n";
	print "  -i	Switch index. Starting with 1. Default is 1.\n";
	print "  -k	Kill all geckodrivers at startup. Default is not to.\n";
	print "  -s	Target device state. \"1\" is on, \"0\" means off.\n";
	print "  -m	Disable headless mode. Default is \"on\". Useful for debugging.\n";
	exit(0);
}

if(defined($options{'h'}) || (!defined($options{'b'}) && (!defined($options{'d'}) || !defined($options{'s'})))){
	VERSION_MESSAGE();
	HELP_MESSAGE();
	exit(-1);
}

if($options{f}){
	my $pid = fork;
	die "Failed to fork: $!" unless defined $pid;
	
	if($pid != 0){
		print STDERR 'Starting scrapper service.'."\n";
		exit;
	}
}

my $configPath = $options->{'c'} || $ENV{'HOME'}.'/.keempleAPI.conf';
my $deviceName = $options{'d'};
my $deviceSwitchIdx = defined($options{'i'}) ? $options{'i'} : 1;
my $targetState = $options{'s'};

our $startTime = undef;
our $scrapper = undef;

# The END block doesn't terminate the geckodriver gently enough when receiving a SIGTERM or SIGKILL.
$SIG{TERM} = sub { if($scrapper){ $scrapper->cleanup(); }; exit; };
$SIG{KILL} = sub { if($scrapper){ $scrapper->cleanup(); }; exit; };

sub readConf {
	my $confPath = shift;
	if(! -e $confPath){
		print 'Conf file "'.$confPath.'" does not exist.'."\n";
		exit(-1);
	}
	my $confData = Config::INI::Reader->read_file($confPath);
	foreach my $var ('login', 'password', 'driver'){
		if(!defined($confData->{'_'}->{'login'})){
			print 'No '.$var.' defined in config file. Is the config file outdated?'."\n";
			exit(-3);
		}
	}
	our $login = Text::Trim::trim($confData->{'_'}->{'login'});
	our $password = Text::Trim::trim($confData->{'_'}->{'password'});
	our $driverType = Text::Trim::trim($confData->{'_'}->{'driver'}); # standalone / integrated
	return ($login, $password, $driverType);
}

sub tic {
	$startTime = time;
}

sub toc {
	my $stopTime = time;
	print 'Execution time: '.($stopTime - $startTime).'s.'."\n";
}

sub initScrapper {
	my ($configType, $options) = @_;
	my ($login, $password, $driverType) = readConf($configPath);
	$scrapper = new KeempleAPI::SeleniumScrapper(	driverType => $driverType,
							disableHeadless => $options->{m},
							login => $login,
							password => $password,
							debug => $options->{g});			
}

tic();

if($options{k}){
	`killall geckodriver 2>/dev/null`;
}

if($options{b}){
	initScrapper($configType, \%options);
	
	my $scrapperServiceObj = KeempleAPI::ScrapperDBusService->new();
	$scrapperServiceObj->initScrapper($scrapper);

	my $reactor = Net::DBus::Reactor->main();
	$reactor->run();
}else{
#	my $dbusService = KeempleAPI::ScrapperDBusService::checkIfInstanceIsAvailable();
#	if($dbusService){
#		print STDERR 'Using DBus method.'."\n";
#		$dbusService->performAction($deviceName, $deviceSwitchIdx, $targetState);
#	}else{
		print STDERR 'Using standalone script.'."\n";
		initScrapper($configType, \%options);
		use Data::Dump;
		Data::Dump::dump $scrapper->getSwitches();
#		Data::Dump::dump $scrapper->refreshSwitchesStates(); # TODO?
#		$scrapper->performAction($deviceName, $deviceSwitchIdx, $targetState);
#	}
}

#undef($KeempleAPI::ScrapperDBusService::scrapperObj);
#undef($scrapper);

END {
	if($scrapper){
		$scrapper->cleanup();
	}
	sleep(2); # Let the browser die in peace.
}

toc();
