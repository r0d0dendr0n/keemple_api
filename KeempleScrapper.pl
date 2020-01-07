#!/usr/bin/perl -CA

# java -jar -Dwebdriver.gecko.driver=/usr/bin/geckodriver /usr/share/selenium-server/selenium-server-standalone.jar
# ./KeempleScrapper.pl ~/.keempleAPI.conf 'głośniki salon' 1 1
# ./KeempleScrapper.pl ~/.keempleAPI.conf 'światło salon' 2 1

use File::Slurp;
use Selenium::Firefox;
use Selenium::Remote::WDKeys;
use Text::Trim;

use utf8;
no warnings 'utf8';

my $confPath = $ARGV[0];
if(! -e $confPath){
	print 'Conf file does not exist.'."\n";
	exit -1;
}
my @confData = File::Slurp::read_file($confPath); # Login\npassword\nstandalone|integrated
my $login = Text::Trim::trim($confData[0]);
my $password = Text::Trim::trim($confData[1]);
my $driverType = Text::Trim::trim($confData[2]); # standalone / integrated
my $device = $ARGV[1];
my $deviceSwitchIdx = $ARGV[2];
my $targetState = $ARGV[3];

my $startTime = time;

my $driver = undef;
if($driverType eq 'standalone'){
	$driver = Selenium::Remote::Driver->new('browser_name' => 'firefox');
}elsif($driverType eq 'integrated'){
	$driver = Selenium::Firefox->new(
		marionette_enabled => 1,
#		custom_args => '--headless' # Somehow doesn't work
	);
}else{
	print 'Unknown driver type: "'.$driverType.'". Must be one of "standalone" or "integrated".'."\n";
	exit -2;
}

$driver->set_implicit_wait_timeout(5000);

$driver->get('https://login.keemple.com');

my $loginField = $driver->find_element_by_id('inputIdentity');
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

$driver->get('https://login.keemple.com/devices/quick_controls');

my $searchField = $driver->find_element_by_xpath('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input');
$searchField->send_keys($device, KEYS->{'enter'});

sleep(1);

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

my $stopTime = time;
print 'Execution time: '.($stopTime - $startTime).'s.'."\n";

# TODO: Is the gateway offline?
# TODO: Select gateway
