package KeempleAPI::SeleniumScrapper;

use Selenium::Firefox;
use Selenium::Remote::WDKeys;
use Text::Trim;
use Try::Tiny;

use utf8;
no warnings 'utf8';

# java -jar -Dwebdriver.gecko.driver=/usr/bin/geckodriver /usr/share/selenium-server/selenium-server-standalone.jar
# DISPLAY=:1 xvfb-run java -jar selenium-server-standalone-2.0b3.jar

sub new {
	my $className = shift;
	my %options = @_;
	my $self = {
		driver => undef,
		driverType => $options{driverType} || 'integrated',
		disableHeadless => $options{disableHeadless},
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
#    $self->cleanup();  
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
	while(!$found && $cnt>0){
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
	
	$self->{driver}->get('https://login.keemple.com/devices/quick_controls');

	my $searchField = $self->waitForField('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/div/div/md-autocomplete/md-autocomplete-wrap/input', 'xpath');
	if(!$searchField){
		print "Unable to find device search field.\n";
		return 0;
	}
	$searchField->send_keys($deviceName, KEYS->{'enter'});
	
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
	
	my $switchStateElement = $self->itemExists('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div/md-switch', 'xpath');
	if(!$switchStateElement){
		$self->dbgMsg('Unable to fetch switch current state');
		return 0;
	}
	my $switchState = $switchStateElement->get_attribute('aria-checked', 1);
	print 'Was: '.($switchState eq 'true' ? 1 : 0).' (raw value: '.$switchState.')'."\n";
	if(($targetState eq '1' && $switchState ne 'true') || ($targetState eq '0' && $switchState ne 'false')){
		print 'Switching state to: '.$targetState.'.'."\n";
		# Try light switch
		my $switchField = $self->itemExists('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div['.$deviceSwitchIdx.']/div/div/div', 'xpath');
		if($switchField){
			print 'Switch flipped!'."\n"; # TODO 2nd check of switchStateElement?
			$switchField->click();
		}else{
			$self->dbgMsg('Error: Unable to flip switch!'."\n");
			return 0;
		}
	}else{
		print 'Already in target state: '.$targetState.'.'."\n";
	}
	return 1;
}

sub performAction {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState) = @_;

	# TODO: Is the gateway offline?
	# TODO: Select gateway
	my $success = $self->performLogin($self->{login}, $self->{password});
	if($success){
		$success = $self->findSwitchQuickControl($deviceName, $deviceSwitchIdx);
	}else{
		print 'Login failed. Aborting'."\n";
		return 0;
	}
	if($success){
		$success = $self->flipSwitch($deviceSwitchIdx, $targetState);
	}else{
		print 'Unable to find switch quick control panel. Aborting'."\n";
		return 0;
	}
	if(!$success){
		print 'Unable to flip the switch'."\n";
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
		warn $msg;
	}
}

1;
