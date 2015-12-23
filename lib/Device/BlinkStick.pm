
# ABSTRACT:

=head1 NAME

Device::BlinkStick

=head1 SYNOPSIS

    use 5.10.0 ;
    use strict ;
    use warnings ;
    use Device::BlinkStick;

    my $bs = Device::BlinkStick->new() ;
    # get the first blinkstick found
    my $device = $bs->first() ;
    # make it red
    $first->set_color( 'red') ;

    sleep( 2) ;
    # blink red for 5s (5000ms) on and off for 250ms
    $first->blink( 'red', 5000, 250) ;    

=head1 DESCRIPTION

See Also 

=head2 left to do from python version

    def _usb_get_string(self, device, length, index):
    def get_led_data(self):
    def data_to_message(self, data):
    def set_random_color(self):
    def turn_off(self):
    def pulse(self, red=0, green=0, blue=0, name=None, hex=None, repeats=1, duration=1000, steps=50):
    def blink(self, red=0, green=0, blue=0, name=None, hex=None, repeats=1, delay=500):
    def morph(self, red=0, green=0, blue=0, name=None, hex=None, duration=1000, steps=50):
    def open_device(self, d):

=over 4

=cut

package Device::BlinkStick ;

use 5.014 ;
use warnings ;
use strict ;
use Moo ;
use Device::USB ;
use Device::BlinkStick::Stick ;

# ----------------------------------------------------------------------------

use constant VENDOR_ID   => 0x20a0 ;
use constant PRODUCT_ID  => 0x41e5 ;
use constant UPDATE_TIME => 2 ;

# ----------------------------------------------------------------------------

# mapping of serial IDs to device info
has devices => ( is => 'ro', init_arg => 0 ) ;
# the first device found
has first => ( is => 'ro', init_arg => 0 ) ;
has verbose => ( is => 'ro' ) ;
has inverse => ( is => 'ro' ) ;

# ----------------------------------------------------------------------------

=item new

=over 4

=item devices

Get all blinkstick devices available

=item first

Get the first blicnk stick device found

=item verbose

output some debug as things happen

=back

=cut

sub BUILD
{
    my $self = shift ;
    my $args = shift ;

    # find the sticks
    $self->refresh_devices() ;
}

# ----------------------------------------------------------------------------
# find all the blinkstick devices

sub refresh_devices
{
    state $last = 0 ;
    my $self = shift ;

    # we don't want to update this too often as it takes ~ 0.4s to run
    if ( !$last || $last + UPDATE_TIME < time() ) {
        $last = time() ;
        my $usb = Device::USB->new() ;
        my @sticks = $usb->list_devices( VENDOR_ID, PRODUCT_ID ) ;

        # find all devices
        if ( scalar(@sticks) ) {
            delete $self->{first} ;
            $self->{devices} = {} ;
            foreach my $dev (@sticks) {
                my $device = Device::BlinkStick::Stick->new( device => $dev, verbose => $self->verbose(), inverse => $self->inverse() ) ;
                if ( !$self->{first} ) {
                    $self->{first} = $device ;
                }
                # build the mapping of devices
                $self->{devices}->{ lc($device->serial_number()) } = $device ;
            }
        }
    }

    return $self->{devices} ;
}

=back

=cut 

# ----------------------------------------------------------------------------
1 ;

