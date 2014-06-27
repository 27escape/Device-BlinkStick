
# ABSTRACT:

=head1 NAME

Device::BlinkStick

=head1 SYNOPSIS

    use 5.10.0 ;
    use strict ;
    use warnings ;
    use Device::BlinkStick;

    my $object = Device::BlinkStick->new() ;

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

package Device::BlinkStick;

use 5.014;
use warnings;
use strict;
use Moo;
use Device::USB;
use Data::Printer;
use Data::Hexdumper;

# ----------------------------------------------------------------------------

use constant VENDOR_ID       => 0x20a0;
use constant PRODUCT_ID      => 0x41e5;
use constant DEFAULT_TIMEOUT => 1000;

# ----------------------------------------------------------------------------

has inverse     => ( is => 'ro' );
has serial_num  => ( is => 'ro' );
has device_name => ( is => 'ro' );

has _device => ( is => 'ro', init_arg => 0 );
has verbose => ( is => 'ro' );

# ----------------------------------------------------------------------------

=item new

Create an instance of a blink stick, will either connect a stick with a given
serial_number, device_name or just the first one thats found

=over 4

=item verbose

output some debug as things happen

=item serial_number

optionally find this stick

=item device_name

optionally find this stick, if serial_number is also defined that will over-ride
I am working on the premise that the device name is stored in info_block_1

=back

=cut

sub BUILD
{
    my $self = shift;
    my $args = shift;

    # find the stick
    $self->_refresh_device();
    if ( $self->verbose ) {
        my $info = $self->info();

        say p($info);
    }
}

# ----------------------------------------------------------------------------

=item info

get a hash of info about the device

=cut

sub info
{
    my $self = shift;

    return {
        device => sprintf( "%04X:%04X",
            $self->{_device}->idVendor(),
            $self->{_device}->idProduct() ),
        manufacturer => $self->get_manufacturer(),
        product      => $self->get_description(),
        serial       => $self->get_serial(),
        info1        => $self->get_info_block1(),
        info2        => $self->get_info_block2(),
    };
}

# ----------------------------------------------------------------------------
# find the device based on info we know

sub _refresh_device
{
    my $self = shift;

    my $usb = Device::USB->new();
    my @sticks = $usb->list_devices( VENDOR_ID, PRODUCT_ID );

    # find all matching devices and then either try to match the requested
    # serial number or string stored in infoblock1 which I am using as the
    # name of the device
    # otherwise if these are not set, then we will use the first stick found
    if ( scalar(@sticks) ) {
        foreach my $s (@sticks) {
            $s->open();
            if ( $self->{serial_num}
                && lc( $s->serial_number() ) eq lc( $self->{serial_num} ) ) {
                $self->{_device} = $s;
                last;
            }
            elsif ( $self->{device_name}
                && lc( $self->_get_info_block(1) ) eq lc( $self->{device_name} ) ) {
                $self->{_device} = $s;
                last;
            }
        }

        # pick the first one if no other match
        if ( !$self->{_device} && !( $self->{serial_num} || $self->{device_name} ) ) {
            $self->{_device} = $sticks[0];
            # make sure we connect to the same one next time around
            $self->{serial_num} = $self->get_serial();
        }
    }
    if ( !$self->{_device} ) {
        die "Could not find BlinkStick";
    }
}

# ----------------------------------------------------------------------------
# usb read sets the 0x80 flag
# read the usb

sub _usb_read
{
    my $self = shift;
    my ( $b_request, $w_value, $w_index, $w_length, $timeout ) = @_;
    $timeout ||= DEFAULT_TIMEOUT;    # we will not allow indefinite timeouts

    # check we still have the device before we do anything, will die if not
    $self->_refresh_device();

    my $bytes = ' ' x $w_length;
    my $bm_requesttype = 0x80 | 0x20;   # 0x80 is LIBUSB_ENDPOINT_IN ie read data in
         # 0x20 is LIBUSB_REQUEST_TYPE_CLASS (0x01 << 5)
    my $count =
        $self->{_device}
        ->control_msg( $bm_requesttype, $b_request, $w_value, $w_index, $bytes,
        $w_length, $timeout );

    say STDERR "USB READ $b_request-$w_value-$w_index\n"
        . hexdump( data => $bytes, suppress_warnings => 1 )
        if ( $self->verbose );

    if ( $count != $w_length ) {
        if ( $count < 0 ) {
            warn "Error reading USB device";

        }
        else {
            warn "unknown error reading USB";

        }

        # if we did not read it all or read nothing, clear it
        $bytes = undef;
    }

    return $bytes;
}

# ----------------------------------------------------------------------------
# consistent way to write

sub _usb_write
{
    my $self = shift;
    my ( $b_request, $w_value, $w_index, $bytes, $w_length, $timeout ) = @_;

    # check we still have the device before we do anything, will die if not
    $self->_refresh_device();

    $w_length //= length($bytes);
    $timeout ||= DEFAULT_TIMEOUT;    # we will not allow indefinite timeouts

    say STDERR "USB WRITE $b_request-$w_value-$w_index\n"
        . hexdump( data => $bytes, suppress_warnings => 1 )
        if ( $self->verbose );

    # 0x00 is LIBUSB_ENDPOINT_OUT ie write data out
    # 0x20 is LIBUSB_REQUEST_TYPE_CLASS (0x01 << 5)
    my $bm_requesttype = 0x20;
    my $count =
        $self->{_device}
        ->control_msg( $bm_requesttype, $b_request, $w_value, $w_index, $bytes,
        $w_length, $timeout );

    my $status = 0;
    if ( $count != $w_length ) {
        if ( $count < 0 ) {
            warn "Error writing to BlinkStick";
        }
        else {
            warn "Unknown error writing to BlinkStick";
        }
    }
    else {
        $status = 1;
    }
    $status;
}

# ----------------------------------------------------------------------------

=item get_manufacturer

retrieve the manufacturer name

=cut

sub get_manufacturer
{
    my $self = shift;

    $self->{_device}->manufacturer();
}

# ----------------------------------------------------------------------------

=item get_description

retrieve the device description

=cut

sub get_description
{
    my $self = shift;

    $self->{_device}->product();
}

# ----------------------------------------------------------------------------

=item get_serial

retrieve the device serial number

=cut

sub get_serial
{
    my $self = shift;

    $self->{_device}->serial_number();
}

# ----------------------------------------------------------------------------
# read one of the info blocks

sub _get_info_block
{
    my $self = shift;
    my ($id) = @_;

    my $bytes = $self->_usb_read( 0x1, $id + 1, 0x0000, 33 );

    if ($bytes) {    # first byte may be the id number, followed by the string
        my ( $ignore, $newbytes ) = unpack( "CZ[32]", $bytes );
        $bytes = $newbytes;
    }
    $bytes;
}

# ----------------------------------------------------------------------------

=item get_info_block1

get the contents of info_block_1, maybe the device name?

=cut

sub get_info_block1
{
    my $self = shift;

    $self->_get_info_block(1);
}

# ----------------------------------------------------------------------------

=item get_info_block2

get the contents of get_info_block_2, maybe the acccess token for the online service?

=cut

sub get_info_block2
{
    my $self = shift;

    $self->_get_info_block(2);
}

# ----------------------------------------------------------------------------
# write into the info block
# id - block number
# str, the string to write, will get trimmed to 32 bytes

sub _set_info_block
{
    my $self = shift;
    my ( $id, $str ) = @_;

    $str //= '';    # empty if thats what they want
    $str = substr( $str, 0, 32 ) if ( length($str) > 32 );

    # packup the string, the first byte seems to be the id number or something
    my $block = pack( "CZ[32]", $id + 1, $str );
    $self->_usb_write( 0x9, $id + 1, 0x0000, $block );
}

# ----------------------------------------------------------------------------

=item set_info_block1

=over 4

=item str

string to write into info_block_1, the device name?

This will get trimmed to 32 characters

=back

returns true/false depending if the string was set

=cut

sub set_info_block1
{
    my $self = shift;
    my $str  = shift;

    $self->_set_info_block( 1, $str );
}

# ----------------------------------------------------------------------------

=item set_info_block2

=over 4

=item str

string to write into info_block_2, the online access token?

This will get trimmed to 32 characters

=back

returns true/false depending if the string was set

=cut

sub set_info_block2
{
    my $self = shift;
    my $str  = shift;

    $self->_set_info_block( 2, $str );
}

# ----------------------------------------------------------------------------

=item get_mode

returns the display mode

0 normal 
1 inverse
2 WS2812

=cut

sub get_mode
{
    my $self = shift;

    my $bytes = $self->_usb_read( 0x1, 0x0004, 0x0000, 2 );

    if ($bytes) {    # first byte may be the id number, followed by the string
        my ( $ignore, $newbytes ) = unpack( "CC", $bytes );
        $bytes = $newbytes;
    }
    $bytes;
}

# ----------------------------------------------------------------------------

=item set_mode

Set the display mode

=over 4

=item mode

mode to set 

0 normal 
1 inverse
2 WS2812

=back

returns true/false depending if the mode was set

=cut

sub set_mode
{
    my $self = shift;
    my $mode = shift;

    if ( $mode < 0 || $mode > 2 ) {
        warn "Invalid mode";
        return 0;
    }

    my $block = pack( "CZ[32]", 0, $mode );
    $self->_usb_write( 0x9, 0x0004, 0x0000, $block );
}

# ----------------------------------------------------------------------------

=item get_color

returns the color as rgb

=cut

sub get_color
{
    my $self = shift;

    my $bytes = $self->_usb_read( 0x1, 0x0001, 0x0000, 4 );
    my ( $r, $g, $b );

    if ($bytes) {    # first byte may be the id number, followed by the string
        my $ignore;
        ( $ignore, $r, $g, $b ) = unpack( "CCCC", $bytes );
        if ( $self->inverse ) {
            ( $r, $g, $b ) = ( 255 - $r, 255 - $g, 255 - $b );
        }
    }
    ( $r, $g, $b );
}

# ----------------------------------------------------------------------------

=item set_color

set the rgb color for a single pixel blinkstick

=over 4

=item r

red part 0..255

=item g

green part 0..255

=item b

blue part 0..255

=back

returns true/false depending if the mode was set

=cut

sub set_color
{
    my $self = shift;
    my ( $r, $g, $b, $channel, $index ) = @_;

    # make sure values are in range
    $r //= 0;
    $g //= 0;
    $b //= 0;
    ( $r, $g, $b ) = ( $r & 255, $g & 255, $b & 255 );

    if ( $self->inverse ) {
        ( $r, $g, $b ) = ( 255 - $r, 255 - $g, 255 - $b );
    }

    if (0) {
        my $block = pack( "CCCCCC", 0, $channel, $index, $r, $g, $b );

        # to write to a multi pixel device
        $self->_usb_write( 0x9, 0x0005, 0x0000, $block, length($block) );
    }
    else {
        my $block = pack( "CCCC", 0, $r, $g, $b );
        $self->_usb_write( 0x9, 0x0001, 0x0000, $block, length($block) );
    }
}

=back

=cut 

# ----------------------------------------------------------------------------
1;

