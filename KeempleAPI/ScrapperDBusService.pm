package KeempleAPI::ScrapperDBusService;

# TODO: Implement a timeout subroutine to periodicaly check if we're still logged in.
# TODO: Handle bad password at init.
# TODO: Ensure the access to performAction is serialized.

use base qw(Net::DBus::Object);
use Net::DBus::Exporter qw(KeempleAPI.ScrapperDBusService);
 
use Class::MethodMaker;

use Encode;

use utf8;
no warnings 'utf8';

our $scrapperObj = undef;
our $serviceName = 'KeempleAPI.ScrapperDBusService';
our $interfaceName = 'KeempleAPI.ScrapperDBusService';
our $interfacePath = '/KeempleAPI/ScrapperService';

sub new {
	my $className = shift;
	
	my $bus = Net::DBus->find();
	my $serviceObj = $bus->export_service($serviceName);
	my $self = $className->SUPER::new($serviceObj, $interfacePath);
		
	bless $self, $className;
	
	return $self;
}

dbus_method('performAction', ['string', 'int32', 'int32'], ['int32'], { param_names => ['deviceName', 'deviceSwitchIdx', 'targetState'], return_names => ['reply'] });
sub performAction {
	my ($self, $deviceName, $deviceSwitchIdx, $targetState) = @_;
	# Strings comes encoded, so we need to decode them, unless we want some shitty characters.
	my $success = $scrapperObj->performAction(decode_utf8($deviceName), $deviceSwitchIdx, $targetState, 1);
	return $success;
}

dbus_method('exit', []);
sub exit {
	my ($self) = @_;
	exit;
}

dbus_method('reinitScrapper', []);
sub reinitScrapper {
	my ($self) = @_;
	
	$scrapperObj->performLogin($scrapperObj->{login}, $scrapperObj->{password});
	
	return;
}

dbus_method('findNearestSwitchName', ['string'], ['string'], { param_names => ['deviceName'], return_names => ['reply'] });
sub findNearestSwitchName {
	my ($self, $deviceName) = @_;
	# Strings comes encoded, so we need to decode them, unless we want some shitty characters.
	my $name = $scrapperObj->getCachedSwitchName(decode_utf8($deviceName));
	return $name;
}

dbus_method('reloadSwitches', []);
sub reloadSwitches {
	my ($self) = @_;
	
	$scrapperObj->getSwitches(1);
}

dbus_method('refreshSwitches', []);
sub refreshSwitches {
	my ($self) = @_;
	
	$scrapperObj->refreshSwitches();
}

sub initScrapper {
	my ($self, $scrapper) = @_;
	my $success = $scrapper->performLogin($scrapper->{login}, $scrapper->{password});
	if($success){
		$scrapperObj = $scrapper;
		$scrapper->refreshSwitches();
	}else{
		print 'Login failed. Aborting'."\n";
		return 0;
	}
	return $success;
}

sub checkIfInstanceIsAvailable {
	my $self = shift;
	my $bus = Net::DBus->find();

	my $service = $bus->get_service($serviceName);
	my $object = $service->get_object($interfacePath, $interfaceName);

	return $object;
}

1;
