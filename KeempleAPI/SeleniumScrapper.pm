package KeempleAPI::SeleniumScrapper;

use Selenium::Firefox;
use Selenium::Remote::WDKeys;
use Text::Trim;
use Try::Tiny;

use utf8;
no warnings 'utf8';

# java -jar -Dwebdriver.gecko.driver=/usr/bin/geckodriver /usr/share/selenium-server/selenium-server-standalone.jar
# DISPLAY=:1 xvfb-run java -jar selenium-server-standalone-2.0b3.jar

# TODO: Handle bad password at init.

sub new {
	my $className = shift;
	my %options = @_;
	my $self = {
		driver => undef,
		driverType => $options{driverType} || 'integrated',
		disableHeadless => $options{disableHeadless},
		lastDeviceName => '',
		login => $options{login},
		password => $options{password},
		debug => $options{debug},
	};
	
	bless $self, $className;
	
	$self->initDriver();
	
	return $self;
}

sub DESTROY {   
    my $self = shift; 
    $self->dbgMsg('destroying...');
#    $self->cleanup(); # Somehow this does not kill the browser reliably.
} 

sub initDriver {
	my $self = shift;
	my $driverType = shift || $self->{driverType};
	my $disableHeadless = shift || $self->{disableHeadless};
	my $browserArgs = ['--headless'];
	if($disableHeadless){
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
	$self->{driver} = $driver;
	$self->{driver}->set_window_size(1024, 768);
	$self->{driver}->get('about:blank');
	return $driver;
}

sub waitForField {
	my ($self, $elementId, $elementType, $cnt) = (shift, shift, shift || 'id', shift || 5);
	$self->dbgMsg('fetching element '.$elementId);
	my $field = $self->itemExists($elementId, $elementType);
	while(!defined($field) && $cnt>0){
		$self->dbgMsg('not defined: '.$elementId);
		sleep(0.2);
		$field = $self->itemExists($elementId, $elementType);
		$cnt--;
	}
	return $field;
}

sub itemExists {
	my ($self, $elementId, $elementType) = (shift, shift, shift || 'id');
	try {
		$self->dbgMsg('Checking if item exists: '.$elementId);
		my $element = $self->{driver}->find_element($elementId, $elementType);
		return $element;
	} catch {
		return 0;
	};
}

sub performLogin {
	my ($self, $login, $password) = @_;
	
	$self->{driver}->get('https://login.keemple.com');
	
	my $currentUrl = $self->{driver}->get_current_url();
	if(!$self->itemExists('inputIdentity') && $currentUrl ne 'https://login.keemple.com/login'){ #$currentUrl eq 'https://login.keemple.com/gtw_settings'){
		$self->dbgMsg('Already logged in: '.$currentUrl);
		return 1;
	}
	
	my $loginField = $self->waitForField('inputIdentity');
	if(!$loginField){
		# Already logged in?
		if($self->{driver}->get_current_url() eq 'https://login.keemple.com/gtw_settings'){
			$self->dbgMsg('Already logged in');
			return 1;
		}
		$self->dbgMsg('Unable to find login field.');
		return 0;
	}
	$loginField->click();
	$loginField->send_keys($login);
	# /html/body/div[1]/div/md-whiteframe/form/md-content/div/md-input-container[1]/div[2]/div -> This field is required.
	
	my $pwdField = $self->waitForField('inputPassword');
	if(!$pwdField){
		$self->dbgMsg('Unable to find password field.');
		return 0;
	}
	$pwdField->click();
	$pwdField->send_keys($password);
	# /html/body/div[1]/div/md-whiteframe/form/md-content/div/md-input-container[2]/div[2]/div -> This field is required.
	
	my $sendButton = $self->waitForField('loginButton2');
	if(!$sendButton){
		$self->dbgMsg('Unable to send login button.');
		return 0;
	}
	$sendButton->click();
	
	# TODO: Check if login and password fields are not empty.
	my $cnt = 50;
	while($cnt>0){
		if($self->{driver}->get_current_url() eq 'https://login.keemple.com/gtw_settings'){
			$self->dbgMsg('Url says we\'re in.');
			return 1;
		}
		# /html/body/md-toast/div/span[1] (trimmed(content): "Invalid credentials")
		my $invalidCredElement = $self->itemExists('/html/body/md-toast/div/span[1]', 'xpath');
		if($invalidCredElement){
			if(Text::Trim::trim($invalidCredElement->get_text()) eq 'Invalid credentials'){
				$self->dbgMsg('Found "Invalid credentials" text..');
				return 0;
			}
		}
		sleep(0.2);
		$cnt--;
	}
	return 0;
}

sub performLogout {
	my ($self) = @_;

	$self->{driver}->get('https://login.keemple.com/auth/logout');
}

sub findSwitchQuickControl {
	my ($self, $deviceName) = @_;
	my $quickControlsUrl = 'https://login.keemple.com/devices/quick_controls';
	if($self->{driver}->get_current_url() eq $quickControlsUrl){
		$self->dbgMsg('Only clear the search field.'."\n");
		my $clearField = $self->itemExists('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/md-chip/div[2]/button/md-icon', 'xpath');
		if($clearField){
			$self->dbgMsg('Clicking field clear.'."\n");
			$clearField->click();
		}
	}else{
		$self->dbgMsg('Go to the quick controls url.'."\n");
		$self->{driver}->get($quickControlsUrl);
	}

	my $searchField = $self->waitForField('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input', 'xpath');
	if(!$searchField){
		print "Unable to find device search field.\n";
		return 0;
	}
	$searchField->send_keys($deviceName, KEYS->{'enter'});
	$self->{lastDeviceName} = $deviceName;
	
	sleep(1);
}

sub flipSwitch {
	my ($self, $deviceSwitchIdx, $targetState) = @_;
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
	
	my $switchStateXPath = '/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div/md-switch';
	my $switchStateElement = $self->itemExists($switchStateXPath, 'xpath');
	if(!$switchStateElement){
		$self->dbgMsg('Unable to fetch switch current state');
		return 0;
	}
	my $switchState = $switchStateElement->get_attribute('aria-checked', 1);
	print 'Was: '.($switchState eq 'true' ? 1 : 0).' (raw value: '.$switchState.')'."\n";
	if(($targetState eq '1' && $switchState eq 'true') || ($targetState eq '0' && $switchState eq 'false')){
		print 'Already in target state: '.$targetState.'.'."\n";
		return 1;
	}
	
	print 'Switching state to: '.$targetState.'.'."\n";
	# Try light switch
	my $switchXPath = '/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div';
	my $switchField = $self->itemExists($switchXPath, 'xpath');
	if(!$switchField){
		$self->dbgMsg('Error: Unable to find switch item!'."\n");
		return 0;
	}
#	$self->{driver}->mouse_move_to_location($switchField, 10, 10);
#	$self->{driver}->click();
	# https://stackoverflow.com/questions/44912203/selenium-web-driver-java-element-is-not-clickable-at-point-x-y-other-elem
	if($switchField->click()){
		print 'Switch flipped!'."\n"; # TODO 2nd check of switchStateElement?
	}else{
		$self->dbgMsg('Error: Unable to flip switch!'."\n");
		return 0;
	}
	
	return 1;
}

sub performAction {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState, $noLogin) = @_;

	# TODO: Is the gateway offline?
	# TODO: Select gateway
	# TODO: Allow direct switch flipping, without the need to find the proper controls via search field. (This allows us to have uber speed like 0.25s!)
	my $success = 1;
	if(!$noLogin){
		$success = $self->performLogin($self->{login}, $self->{password});
	}
	if(!$success){
		print 'Login failed. Aborting'."\n";
		return 0;
	}
	if($deviceName ne $self->{lastDeviceName}){
		if($self->{lastDeviceName} ne ''){
			$self->dbgMsg('Last device name is different than this. Must clear the search field.'."\n");
		}
		$success = $self->findSwitchQuickControl($deviceName, $deviceSwitchIdx);
	}
	if(!$success){
		print 'Unable to find switch quick control panel. Aborting'."\n";
		return 0;
	}
	$success = $self->flipSwitch($deviceSwitchIdx, $targetState);
	if(!$success){
		print 'Unable to flip the switch'."\n";
		return 0;
	}
	return $success;
}

sub cleanup {
	my $self = shift;
	$self->dbgMsg('cleanup...');
	if($self->{driver}){
		$self->{driver}->shutdown_binary();
	}
	$self->{driver} = undef;
}

sub dbgMsg {
	my ($self, $msg) = @_;
	if($self->{debug}){
		print STDERR $msg;
	}
}

1;
