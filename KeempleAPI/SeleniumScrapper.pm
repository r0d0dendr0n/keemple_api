package KeempleAPI::SeleniumScrapper;

use Selenium::Firefox;
use Selenium::Remote::WDKeys;
use Text::Fuzzy;
use Text::Trim;
use Try::Tiny;

use utf8;
no warnings 'utf8';

# java -jar -Dwebdriver.gecko.driver=/usr/bin/geckodriver /usr/share/selenium-server/selenium-server-standalone.jar
# DISPLAY=:1 xvfb-run java -jar selenium-server-standalone-2.0b3.jar

# TODO: Handle bad password at init.
# TODO: Implement a timeout subroutine to periodicaly refresh states or hook to some Selenium stuff for this data.

sub new {
	my $className = shift;
	my %options = @_;
	my $self = {
		driver => undef,
		driverType => $options{driverType} || 'integrated',
		disableHeadless => $options{disableHeadless},
		lastDeviceName => '',
		controlsRefreshed => 0,
		enableWebSearch => 0,
		switches => undef,
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
			#'accept_ssl_certs' => 1,
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
		my $element = $self->{driver}->find_elements($elementId, $elementType);
		return $element->[0];
	} catch {
		return 0;
	};
}

sub performLogin {
	my ($self, $login, $password) = @_;
	
	my $currentUrl = $self->{driver}->get_current_url();
	if($currentUrl =~ m|^https://login.keemple.com/.+| && !$self->itemExists('inputIdentity')){
		$self->dbgMsg('Already logged in (no url changed): '.$currentUrl);
		return 1;
	}

	# On a different site, but still logged in?	
	$self->{driver}->get('https://login.keemple.com');
	
	$currentUrl = $self->{driver}->get_current_url();
	if($currentUrl ne 'https://login.keemple.com/login' && $currentUrl ne 'https://login.keemple.com/gtw_settings' && !$self->itemExists('inputIdentity')){ #$currentUrl eq 'https://login.keemple.com/gtw_settings'){
		$self->dbgMsg('Already logged in (after going to login page): '.$currentUrl);
		return 1;
	}
	
	my $loginField = $self->waitForField('inputIdentity');
	if(!$loginField){
		# Already logged in?
		if($self->{driver}->get_current_url() eq 'https://login.keemple.com/gtw_settings'){
			$self->dbgMsg('Already logged in (after logging in)');
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

sub gotoQuickControlList {
	my ($self) = @_;
	
	my $quickControlsUrl = 'https://login.keemple.com/devices/quick_controls';
	if($self->{driver}->get_current_url() eq $quickControlsUrl){
		return 0;
	}
	$self->dbgMsg('Go to the quick controls url.'."\n");
	$self->{driver}->get($quickControlsUrl);
	
	return 1;
}

sub findSwitchQuickControl {
	my ($self, $deviceName) = @_;
	
	my $quickControlsStatus = $self->gotoQuickControlList();
	if($quickControlsStatus == 0){
		$self->dbgMsg('Only clear the search field.'."\n");
		my $clearField = $self->itemExists('/html/body/div[1]/div/div/div/md-content/div[1]/div[1]/div[1]/div/md-chips/md-chips-wrap/md-chip/div[2]/button/md-icon', 'xpath');
		if($clearField){
			$self->dbgMsg('Clicking field clear.'."\n");
			$clearField->click();
		}
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

sub getCachedSwitchName {
	my ($self, $deviceName) = @_;
	
	my @switchesNames = keys %{$self->{switches}};
	my $tf = Text::Fuzzy->new($deviceName);
	my $nearest = $tf->nearestv(\@switchesNames);
	
	$self->dbgMsg('Closest cached: '.$nearest);
	
	return $nearest;
}

sub getCachedSwitchControl {
	my ($self, $deviceName, $deviceSwitchIdx) = @_;
	
	my $nearest = $self->getCachedSwitchName($deviceName);
	$self->dbgMsg('Nearest to '.$deviceName.' is: '.$nearest);
	
	if(!$nearest){
		$self->dbgMsg('Nearest is null.');
		return undef;
	}
	
	if(!defined($self->{switches}->{$nearest})){
		$self->dbgMsg('Nearest in switches is null.');
		return undef;
	}
	
	if(!defined($self->{switches}->{$nearest}->{$deviceSwitchIdx})){
		my @keys = keys %{$self->{switches}->{$nearest}};
		$self->dbgMsg('Switch id '.$deviceSwitchIdx.' of nearest in switches. Available are: '.Data::Dump::dump(\@keys));
		return undef;
	}
	
	return $self->{switches}->{$nearest}->{$deviceSwitchIdx};
}

sub getSwitchQuickControl {
	my ($self, $deviceName, $deviceSwitchIdx) = @_;
	
	if(!$self->{controlsRefreshed}){
		return undef;
	}
	
	my $element = $self->getCachedSwitchControl($deviceName, $deviceSwitchIdx);
	#$self->{last_element} = $element->{'element'};
	if(!$element){
		return $self->findSwitchQuickControl($deviceName, $deviceSwitchIdx);
	}
	
	return $element;
}

sub getSwitches {
	my ($self, $force) = @_;
	
	if(!$force && defined($self->{switches})){
		return $self->{switches};
	}
	
	my $success = 1;
	$success = $self->performLogin($self->{login}, $self->{password});
	if(!$success){
		print 'Login failed. Aborting'."\n";
		return 0;
	}
	my $quickControlsStatus = $self->gotoQuickControlList();
	
#	whole element div
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe

#	Label
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/quick-control-header/md-toolbar/div/label
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[2]/md-whiteframe/quick-control-header/md-toolbar/div/label
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[3]/md-whiteframe/quick-control-header/md-toolbar/div/label

#	Device nr 1, switch nr 1
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[1]/div/div/label
#	Device nr 1, switch nr 2
#	/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/div/div[2]/div/div/label

#						 /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[1]/md-whiteframe/quick-control-header/md-toolbar/div/label
#						 /html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span[2]/md-whiteframe/quick-control-header/md-toolbar/div/label

	my $implicitTimeout = $self->{driver}->get_timeouts()->{'implicit'};
	my $switches = {};
	my $labelObjectsXPath = '/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span/md-whiteframe';
	my $labelObjects = $self->{driver}->find_elements($labelObjectsXPath, 'xpath');
	$self->{driver}->set_timeout('implicit', 100);
	my $spanId = 1;
	foreach my $elem (@{$labelObjects}){
		my $labelElem = $self->{driver}->find_child_elements($elem, './quick-control-header/md-toolbar/div/label');
		my $deviceLabel = $labelElem->[0]->get_text();
		$self->dbgMsg('Found device: '.$deviceLabel);
		
		my $elemSwitches = {};
		my $switchObjects = $self->{driver}->find_child_elements($elem, './div/div/div/div/label', 'xpath');
		my $switchId = 1;
		foreach my $switchElem (@{$switchObjects}){
			if(!$switchElem){
				last;
			}
			my $switchLabel = $switchElem->get_text();
			my $switchStateXPath = './div/div['.$switchId.']/div/div/div/md-switch';
			my $switchXPath = './div/div['.$switchId.']/div/div/div';
			my $switchStateElement = $self->{driver}->find_child_elements($elem, $switchStateXPath, 'xpath');
			my $switchElement = ($switchStateElement ? $self->{driver}->find_child_elements($elem, $switchXPath, 'xpath') : undef);
			if(scalar(@{$switchStateElement})==0 || scalar(@{$switchElement})==0){
				$self->dbgMsg('Unable to fetch switch '.$switchId.' current state');
				$switchId++;
				next;
			}
			my $val = $self->getSwitchElementValue($switchStateElement);
			$elemSwitches->{$switchId} = {'id' => $spanId, 'element' => $switchElement->[0], 'elementXPath' => $labelObjectsXPath.substr($switchXPath, 1), 'stateElement' => $labelObjectsXPath.substr($switchStateElement, 1), 'stateElementXPath' => $labelObjectsXPath.substr($switchStateXPath, 1), 'value' => $val};
			$self->dbgMsg('Found switch id '.$switchId.' name '.$switchLabel.' value '.$val);
			$switchId++;
		}
		$switches->{$deviceLabel} = $elemSwitches;
		$spanId++;
	}
	
	$self->{driver}->set_timeout('implicit', $implicitTimeout);
	$self->{switches} = $switches;
	
	$self->dbgMsg('Controls set!');
	$self->{controlsRefreshed} = 1;
	
	return $switches;

#	my $arr = $self->{driver}->find_elements('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span/md-whiteframe/quick-control-header/md-toolbar/div/label', 'xpath');
#	
#	foreach my $el (@{$arr}){
#		warn $el->get_text();
#	}
}

sub refreshSwitches {
	my ($self) = @_;
	
	if(!defined($self->{switches})){
		return $self->getSwitches(1);
	}
	
	my $quickControlsStatus = $self->gotoQuickControlList();
	
	my $implicitTimeout = $self->{driver}->get_timeouts()->{'implicit'};
	$self->{driver}->set_timeout('implicit', 100);
	foreach my $deviceLabel (keys %{$self->{switches}}){
		$self->dbgMsg('Refreshing device: '.$deviceLabel);
		foreach my $switchId (keys %{$self->{switches}->{$deviceLabel}}){
			my $switchStruct = $self->{switches}->{$deviceLabel}->{$switchId};
			my $switchStateXPath = $switchStruct->{'stateElementXPath'};
			my $elemId = $switchStruct->{'id'};
			$switchStateXPath =~ s|/span/|/span[$elemId]/|;
			my $switchStateElement = $self->itemExists($switchStateXPath, 'xpath');
			if(!$switchStateElement){
				$self->dbgMsg('Unable to fetch switch '.$switchId.' current state');
				next;
			}
			my $val = $self->getSwitchElementValue([$switchStateElement]); # Inside it neets to be in an arrayref.
			#$elemSwitches->{$switchId} = {'element' => $switchStateElement, 'value' => $val}; # TODO: element != stateElement
			if($switchStruct->{'value'} != $val){
				$self->dbgMsg('New value for switch id '.$switchId.': '.$val);
				$self->{switches}->{$deviceLabel}->{$switchId}->{'value'} = $val;
			}
		}
	}
	
	$self->{driver}->set_timeout('implicit', $implicitTimeout);
	
	$self->dbgMsg('Controls refreshed!');
	$self->{controlsRefreshed} = 1;
	
	return $self->{switches};

#	my $arr = $self->{driver}->find_elements('/html/body/div[1]/div/div/div/md-content/div[1]/div[2]/div/div/div/span/md-whiteframe/quick-control-header/md-toolbar/div/label', 'xpath');
#	
#	foreach my $el (@{$arr}){
#		warn $el->get_text();
#	}
}

sub getSwitchElementValue {
	my ($self, $switchStateElement) = @_;
	if(ref($switchStateElement) ne 'ARRAY'){
		$self->dbgMsg('Unable to fetch switch element value!');
		return undef;
	}
	my $switchState = $switchStateElement->[0]->get_attribute('aria-checked', 1);
	$self->dbgMsg('aria-checked value: '.$switchState);
	return ($switchState eq 'true' ? 1 : 0);
}

sub flipSwitchCached {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState) = @_;
	
	$self->dbgMsg('Cached flip.');
	if(!$self->{controlsRefreshed}){
		$self->dbgMsg('Controls not refreshed');
		return 0;
	}
	
	my $switchStruct = $self->getCachedSwitchControl($deviceName, $deviceSwitchIdx);
	if(ref($switchStruct) ne 'HASH'){
		$self->dbgMsg('SwitchStruct is null');
		return 0;
	}
	my $switchField = $switchStruct->{'element'};
	if(!$switchField){
		$self->dbgMsg('SwitchField is null');
		return 0;
	}
	my $switchValue = $switchStruct->{'value'};
	print 'Was: '.$switchValue."\n";
	if($targetState == $switchValue){
		print 'Already in target state: '.$targetState.'.'."\n";
		return 1;
	}
	my $success = undef;
	try {
		$success = $switchField->click(); # Elements tend to get "stale";
	} catch {
		$switchField = $self->itemExists($switchStruct->{'elementXPath'}, 'xpath');
		$success = $switchField->click();
	};
	if($success){
		$switchStruct->{'value'} = $targetState; # TODO: This should be an event, sent by the driver.
		print 'Switch flipped!'."\n"; # TODO 2nd check of switchStateElement?
	}else{
		$self->dbgMsg('Error: Unable to flip switch!'."\n");
		return 0;
	}
	return 1;
}

sub flipSwitchNotCached {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState) = @_;
	
	$self->dbgMsg('Not cached flip.');
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
	#my $switchState = $switchStateElement->get_attribute('aria-checked', 1);
	my $switchValue = $self->getSwitchElementValue($switchStateElement);
	print 'Was: '.$switchValue."\n";
	if($targetState == $switchValue){
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

sub flipSwitch {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState) = @_;
	
	if($self->{enableWebSearch}){
		$success = $self->flipSwitchNotCached($deviceName, $deviceSwitchIdx, $targetState);
	}else{
		$success = $self->flipSwitchCached($deviceName, $deviceSwitchIdx, $targetState);
	}
	
	return $success;
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
	$success = $self->flipSwitch($deviceName, $deviceSwitchIdx, $targetState);
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
		print STDERR $msg."\n";
	}
}

1;
