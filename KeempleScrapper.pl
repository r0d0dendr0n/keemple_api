#!/usr/bin/perl -CA

# java -jar -Dwebdriver.gecko.driver=/usr/bin/geckodriver /usr/share/selenium-server/selenium-server-standalone.jar
# DISPLAY=:1 xvfb-run java -jar selenium-server-standalone-2.0b3.jar
# ./KeempleScrapper.pl ~/.keempleAPI.conf 'głośniki salon' 1 1
# ./KeempleScrapper.pl ~/.keempleAPI.conf 'światło salon' 2 1

#Error while executing command: no such element: Unable to locate element: /html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input at /usr/share/perl5/site_perl/Selenium/Remote/Driver.pm line 403.
# at /usr/share/perl5/site_perl/Selenium/Remote/Driver.pm line 353.
# at /usr/share/perl5/site_perl/Selenium/Remote/Finders.pm line 26.
#Unable to find device search field. Probably login failed.

use Config::INI::Reader;
use Getopt::Std;
use Selenium::Firefox;
use Selenium::Remote::WDKeys;
use Text::Trim;
use Try::Tiny;

use utf8;
no warnings 'utf8';

our $VERSION = '0.2';

our %options = ();
Getopt::Std::getopts('c:d:fhs:i:m', \%options);

sub VERSION_MESSAGE {
	print "KeempleScrapper $VERSION\n";
	print "Tomasz Rozynek <Tomasz.Rozynek@dir.pl> ©2020\n\n";
}

sub HELP_MESSAGE {
	print "Usage: KeempleScrapper.pl [-m] [-y] [-c \"config path\"] -d \"device name\" [-i switchIdx] -s targetState\n";
	print "\n";
	print "Options:\n";
	print "-c	Configuration file path. Default is \"~/.keempleAPI.conf\".\n";
	print "-d	Device full display name.\n";
	print "-f	Fork - daemon mode.\n";
	print "-h	Help message.\n";
	print "-i	Switch index. Starting with 1. Default is 1.\n";
	print "-s	Target device state. \"1\" is on, \"0\" means off.\n";
	print "-m	Disable headless mode. Default is \"on\". Useful for debugging.\n";
	exit(0);
}

if(defined($options{'h'}) || (!defined($options{'d'}) || !defined($options{'s'}))){
	VERSION_MESSAGE();
	HELP_MESSAGE();
	exit(-1);
}

my $deviceName = $options{'d'};
my $deviceSwitchIdx = defined($options{'i'}) ? $options{'i'} : 1;
my $targetState = $options{'s'};

our $startTime = undef;
our $driver = undef;

sub readConf {
	my $options = shift;
	my $confPath = $options->{'c'} || $ENV{'HOME'}.'/.keempleAPI.conf';
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

sub initdriver {
	my $options = shift;
	my $browserArgs = ['--headless'];
	if(defined($options->{'m'})){
		$browserArgs = [];
	}
	if($driverType eq 'standalone'){
		$driver = Selenium::Remote::Driver->new('browser_name' => 'firefox');
	}elsif($driverType eq 'integrated'){
		$driver = Selenium::Firefox->new(
			'marionette_enabled' => 1,
			'extra_capabilities' => {
				'moz:firefoxOptions' => {
				"args" => $browserArgs,
				},
			},
		);
	}else{
		print 'Unknown driver type: "'.$driverType.'". Must be one of "standalone" or "integrated".'."\n";
		exit(-2);
	}
	
	$driver->set_implicit_wait_timeout(5000);
	return $driver;
}

sub performLogin {
	my ($driver, $login, $password) = @_;
	
	my $loginField = undef;
	
	$driver->get('https://login.keemple.com');
	
	$loginField = $driver->find_element_by_id('inputIdentity');
	
	# May not be logged in
	if($loginField){
		$loginField->click();
		$loginField->send_keys($login);
		
		my $pwdField = $driver->find_element('inputPassword', 'id');
		$pwdField->click();
		$pwdField->send_keys($password);
		
		my $sendButton = $driver->find_element('loginButton2', 'id');
		$sendButton->click();
	}
	
	my $success = !$driver->find_element_by_id('inputIdentity');
	return $success;
}

sub performLogout {
	my ($driver) = @_;

	$driver->get('https://login.keemple.com/auth/logout');
}

sub findSwitchQuickControl {
	my ($driver, $deviceName) = @_;
	
	$driver->get('https://login.keemple.com/devices/quick_controls');

	my $searchField = $driver->find_element_by_xpath('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input');
	if(!$searchField){
		print "Unable to find device search field. Probably login failed.\n";
		driverCleanup();
		exit(-4);
	}
	$searchField->send_keys($deviceName, KEYS->{'enter'});
	
	sleep(1);
}

sub flipSwitch {
	my ($driver, $deviceSwitchIdx, $targetState) = @_;
	# Światło
	#Nazwy okienek urządzeń (labele):
	#1: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/quick-control-header/md-toolbar/div/label
	#2: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[2]/md-whiteframe/quick-control-header/md-toolbar/div/label
	#
	#Przełączniki w okienku urządzenia:
	#1: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[1]/div/div/label
	#2: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[2]/div/div/label
	#
	#Stan przełącznika: ('true' / 'false')
	#1: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[1]/div/div/div/md-switch/@aria-checked
	#2: /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[2]/div/div/div/md-switch/@aria-checked
	#
	#Kontakt stan przełącznika:
	#   /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span/md-whiteframe/div/div[1]/div/div/div/md-switch
	
	my $switchStateElement = $driver->find_element_by_xpath('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div/md-switch');
	my $switchState = $switchStateElement->get_attribute('aria-checked', 1);
	print 'Was: '.($switchState eq 'true' ? 1 : 0).' (raw value: '.$switchState.')'."\n";
	if(($targetState eq '1' && $switchState ne 'true') || ($targetState eq '0' && $switchState ne 'false')){
		print 'Switching state to: '.$targetState.'.'."\n";
		# Try light switch
		my $switchField = $driver->find_element_by_xpath('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div');
		if($switchField){
			print 'Switch flipped!'."\n"; # TODO 2nd check of switchStateElement?
			$switchField->click();
		}else{
			print 'Error: Unable to flip switch!'."\n";
		}
	}else{
		print 'Already in target state: '.$targetState.'.'."\n";
	}
}

sub toc {
	my $stopTime = time;
	print 'Execution time: '.($stopTime - $startTime).'s.'."\n";
}

sub driverCleanup {
	my $driver = shift;
	$driver->shutdown_binary;
}

sub performAction {
	my ($deviceName, $deviceSwitchIdx, $targetState) = @_;
	our %options;
	my ($login, $password, $driverType) = readConf(\%options);

	# TODO: Is the gateway offline?
	# TODO: Select gateway
	tic();
	my $driver = initdriver(\%options);
	if(!defined($driver)){
		warn 'Driver is null.';
	}
	my $success = performLogin($driver, $login, $password);
#	if($success){
		$success = findSwitchQuickControl($driver, $deviceName, $deviceSwitchIdx);
#	}
#	if($success){
		$success = flipSwitch($driver, $deviceSwitchIdx, $targetState);
#	}
	toc();
	driverCleanup($driver);
}

performAction($deviceName, $deviceSwitchIdx, $targetState);
