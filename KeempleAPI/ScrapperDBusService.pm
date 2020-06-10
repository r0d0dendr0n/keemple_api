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

sub new {
	my $className = shift;
	my $dbusSercice = shift;
	my $self = $className->SUPER::new($dbusSercice, '/KeempleAPI/ScrapperService');
		
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

sub initScrapper {
	my ($self, $scrapper) = @_;
	my $success = $scrapper->performLogin($scrapper->{login}, $scrapper->{password});
	if($success){
		$scrapperObj = $scrapper;
	}else{
		print 'Login failed. Aborting'."\n";
		return 0;
	}
	return $success;
}

1;