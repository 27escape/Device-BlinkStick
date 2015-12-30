
# ABSTRACT:

=head1 NAME

Device::BlinkStick

=head1 SYNOPSIS

    use 5.10.0 ;
    use strict ;
    use warnings ;
    use Device::BlinkStick;

    my $bs = Device::BlinkStick->new() ;

    # set first LED on all devices to blue
    my $all_devices = $bs->devices() ;
    foreach my $k ( keys %$all_devices) {
        $all->{$k}->set_color( 'blue') ;
    }

    # get the first blinkstick found
    my $device = $bs->first() ;
    # make it red
    $first->set_color( 'red') ;

    sleep( 2) ;
    # blink red for 5s (5000ms) on and off for 250ms
    $first->blink( 'red', 5000, 250) ;    

=head1 DESCRIPTION

Module to control a number of blinkstick devices L<http://blinkstick.com> connected via USB.

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

=head2 new

Instantiate a new object, also finds all currently connected devices and populates 
the accessor method variables

=head3 parameters

=over 4

=item verbose

output some debug as things happen

=back

=head3 access methods

=over 4

=item devices

Get all blinkstick device objects available as a hash ref

    my $bs = Device::BlinkStick->new() ;
    my $devices = $bs->devices() ;

=item first

Get the first blink stick device (object) found

    my $bs = Device::BlinkStick->new() ;
    my $device = $bs->first() ;
    # make it red
    $first->set_color( 'red') ;

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
# find all the connected blinkstick devices

=head2 refresh_devices

Check the USB for any added or removed devices and update our internal list

Returns all blinkstick device objects available as a hash ref

    my $bs = Device::BlinkStick->new() ;
    my $current = $bs->refresh_devices() ;

=cut

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
                my $device = Device::BlinkStick::Stick->new(
                    device  => $dev,
                    verbose => $self->verbose(),
                    inverse => $self->inverse()
                ) ;
                if ( !$self->{first} ) {
                    $self->{first} = $device ;
                }
                # build the mapping of devices
                $self->{devices}->{ lc( $device->serial_number() ) }
                    = $device ;
            }
        }
    }

    return $self->{devices} ;
}

# ----------------------------------------------------------------------------
# find a matching device

=head2 find

Find a device by name or serial number

    my $bs = Device::BlinkStick->new() ;
    my $d = $bs->find( 'strip') ;   # I have a device I've named strip!
    $d->set_mode( 3) ;
    $d->set_color( 'green') ;       # set all LEDs to green

=over 4

=item name

The name or serial number to match

=back

Returns undef if fails to match a device

=cut

sub find
{
    my $self = shift ;
    my ($name) = @_ ;
    my $stick ;

    $name = lc($name) ;
    # check match on serial number
    if ( $self->{devices}->{$name} ) {
        $stick = $self->{devices}->{$name};
    } else {
        # match against each device name
        foreach my $s ( keys %{ $self->{devices} } ) {
            if ( lc( $self->{devices}->{$s}->device_name ) eq $name ) {
                $stick = $self->{devices}->{$s} ;
            }
        }
    }
    return $stick ;
}

# ----------------------------------------------------------------------------
1 ;

