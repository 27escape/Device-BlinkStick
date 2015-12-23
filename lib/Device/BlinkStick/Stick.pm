
# ABSTRACT:

=head1 NAME

Device::BlinkStick::Stick

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

Object holding information and control about a specic blinkstick device

See Also 

=head2 left to do from python version

    def _usb_get_string(self, device, length, index):
    def get_led_data(self):
    def data_to_message(self, data):
    def set_random_color(self):
    def turn_off(self):
    def blink(self, red=0, green=0, blue=0, name=None, hex=None, repeats=1, delay=500):

=over 4

=cut

package Device::BlinkStick::Stick ;

use 5.014 ;
use warnings ;
use strict ;
use Moo ;
use Data::Hexdumper ;
use Time::HiRes qw(usleep) ;

use Data::Printer ;

# ----------------------------------------------------------------------------

use constant DEFAULT_TIMEOUT => 1000 ;
use constant EMULATE_LEDS => 16 ;
use constant EMULATE_DELAY_USECS => 500 ;

# ----------------------------------------------------------------------------

has device  => ( is => 'ro' ) ;
has verbose => ( is => 'rw' ) ;
has inverse => ( is => 'rw' ) ;

has serial_number => ( is => 'ro', init_arg => 0 ) ;
has device_name   => ( is => 'ro', init_arg => 0 ) ;
has _leds         => ( is => 'ro', init_arg => 0 ) ;
has type          => ( is => 'ro', init_arg => 0 ) ;
has brightness    => (
    is       => 'rw',
    init_arg => 0,
    isa      => sub {
        if ( $_[0] > 100 ) {
            print STDERR "Brightness too high\n" ;
            $_[0] = 100 ;
        }
    }
) ;

# ----------------------------------------------------------------------------

=item new

Create an instance of a blink stick device, requires an open USB file device

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
    my $self = shift ;
    my $args = shift ;

    $args->{device}->open() ;
    $self->{verbose} = $args->{verbose} ;
    $self->{serial_number} = $self->{device}->serial_number() || "" ;
    # get the rest of the info
    $self->{device_name} = $self->get_device_name() || "" ;
    $self->{_leds}       = $self->get_leds() ;
    $self->{_mode}       = $self->get_mode() ;
    $self->{type}
        = ( $self->{serial_number} =~ /-1\.[0-9]$/ )
        ? "original"
        : "pro" ;
}

# ----------------------------------------------------------------------------

=item info

get a hash of info about the device

=cut

sub info
{
    my $self = shift ;

    return {
        device => sprintf( "%04X:%04X",
            $self->{device}->idVendor(),
            $self->{device}->idProduct() ),
        manufacturer  => $self->{device}->manufacturer(),
        product       => $self->{device}->product(),
        serial_number => $self->{serial_number},
        device_name   => $self->{device_name},
        access_token  => $self->get_access_token() || "",
        leds          => $self->{_leds},
        mode          => defined $self->{_mode} ? $self->{_mode} : 0,
        color         => [ $self->get_color() ],
        type          => $self->type,
    } ;
}

# ----------------------------------------------------------------------------
# usb read sets the 0x80 flag
# read the usb

sub _usb_read
{
    my $self = shift ;
    my ( $b_request, $w_value, $w_index, $w_length, $timeout ) = @_ ;
    $timeout ||= DEFAULT_TIMEOUT ;    # we will not allow indefinite timeouts

    my $bytes = ' ' x $w_length ;
    my $bm_requesttype
        = 0x80 | 0x20 ;    # 0x80 is LIBUSB_ENDPOINT_IN ie read data in
                           # 0x20 is LIBUSB_REQUEST_TYPE_CLASS (0x01 << 5)
    my $count
        = $self->{device}
        ->control_msg( $bm_requesttype, $b_request, $w_value, $w_index,
        $bytes, $w_length, $timeout ) ;

    if ( $self->verbose ) {
        say STDERR "USB READ $b_request-$w_value-$w_index ($w_length)\n"
            . hexdump( data => $bytes, suppress_warnings => 1 )
            . "read $count bytes" ;
    }

    if ( $count != $w_length && $self->verbose) {
        if ( $count < 0 ) {
            warn
                "Error reading USB device _usb_read( $b_request, $w_value, $w_index, $w_length)"
;
        } else {
            warn
                "unknown error reading USB _usb_read( $b_request, $w_value, $w_index, $w_length)"
 ;
        }

        # if we did not read it all or read nothing, clear it
        $bytes = undef ;
    }

    return $bytes ;
}

# ----------------------------------------------------------------------------
# consistent way to write

sub _usb_write
{
    my $self = shift ;
    my ( $b_request, $w_value, $w_index, $bytes, $w_length, $timeout ) = @_ ;

    $w_length //= length($bytes) ;
    $timeout ||= DEFAULT_TIMEOUT ;    # we will not allow indefinite timeouts

    # 0x00 is LIBUSB_ENDPOINT_OUT ie write data out
    # 0x20 is LIBUSB_REQUEST_TYPE_CLASS (0x01 << 5)
    my $bm_requesttype = 0x20 ;
    my $count
        = $self->{device}
        ->control_msg( $bm_requesttype, $b_request, $w_value, $w_index,
        $bytes, $w_length, $timeout ) ;

    if ( $self->verbose ) {
        say STDERR "USB WRITE $b_request-$w_value-$w_index\n"
            . hexdump( data => $bytes, suppress_warnings => 1 )
            . "wrote $count bytes" ;
    }
    my $status = 0 ;
    if ( $count != $w_length && $self->verbose) {
        if ( $count < 0 ) {
            warn "Error writing to BlinkStick";
        } else {
            warn "Unknown error writing to BlinkStick" ;
        }
    } else {
        $status = 1 ;
    }
    $status ;
}


# ----------------------------------------------------------------------------
# read one of the info blocks

sub _get_info_block
{
    my $self = shift ;
    my ($id) = @_ ;

    print STDERR "_get_info_block $id " if ( $self->verbose ) ;
    my $bytes = $self->_usb_read( 0x1, $id + 1, 0, 33 ) ;

    if ($bytes) {    # first byte may be the id number, followed by the string
        my ( $ignore, $newbytes ) = unpack( "CZ[32]", $bytes ) ;
        $bytes = $newbytes ;
    }
    $bytes ;
}

# ----------------------------------------------------------------------------

=item get_device_name

get the contents of info_block_1, usually the device name?

=cut

sub get_device_name
{
    my $self = shift ;

    $self->_get_info_block(1) ;
}

# ----------------------------------------------------------------------------

=item get_access_token

get the contents of get_info_block_2, maybe the acccess token for the online service?
unused for perl

=cut

sub get_access_token
{
    my $self = shift ;

    $self->_get_info_block(2) ;
}

# ----------------------------------------------------------------------------
# write into the info block
# id - block number
# str, the string to write, will get trimmed to 32 bytes

sub _set_info_block
{
    my $self = shift ;
    my ( $id, $str ) = @_ ;

    $str //= '' ;    # empty if thats what they want
    $str = substr( $str, 0, 32 ) if ( length($str) > 32 ) ;

    # packup the string, the first byte seems to be the id number or something
    my $block = pack( "CZ[32]", $id + 1, $str ) ;
    print STDERR "_set_info_block $id " if ( $self->verbose ) ;
    $self->_usb_write( 0x9, $id + 1, 0, $block ) ;
}

# ----------------------------------------------------------------------------

=item set_device_name

=over 4

=item str

string to write into info_block_1, the device name

This will get trimmed to 32 characters

=back

returns true/false depending if the string was set

=cut

sub set_device_name
{
    my $self = shift ;
    my $str  = shift ;

    $self->_set_info_block( 1, $str ) ;
}

# ----------------------------------------------------------------------------

=item set_access_token

=over 4

=item str

string to write into info_block_2, the online access token. Not used by perl

This will get trimmed to 32 characters

=back

returns true/false depending if the string was set

=cut

sub set_access_token
{
    my $self = shift ;
    my $str  = shift ;

    $self->_set_info_block( 2, $str ) ;
}

# ----------------------------------------------------------------------------

=item get_mode

returns the display mode

0 normal 
1 inverse
2 WS2812
3 WS2812 mirror - all leds the same

=cut

sub get_mode
{
    my $self = shift ;

    print STDERR "_get_mode " if ( $self->verbose ) ;
    my $bytes = $self->_usb_read( 0x1, 4, 0, 2 ) ;

    if ($bytes) {    # first byte may be the id number, followed by the string
        my ( $ignore, $newbytes ) = unpack( "CC", $bytes ) ;
        $bytes = $newbytes ;
    }
    $bytes ;
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
3 WS2812 mirror - all leds the same

=back

returns true/false depending if the mode was set

=cut

sub set_mode
{
    my $self = shift ;
    my $mode = shift ;

    if ( $mode < 0 || $mode > 3 ) {
        warn "Invalid mode" ;
        return 0 ;
    }

    # mode 3 is emulated
    if ( $mode < 3 ) {
        my $block = pack( "CC", 4, $mode ) ;
        print STDERR "set_mode " if ( $self->verbose ) ;
        $self->_usb_write( 0x9, 4, 0, $block ) ;
    }
    $self->{_mode} = $mode ;
}

# ----------------------------------------------------------------------------

=item get_color

returns the color as rgb

=cut

sub get_color
{
    my $self = shift ;
    my ( $channel, $index ) = @_ ;

    $channel //= 0 ;
    $index   //= 0 ;
    if ( !$self->{_type} || $self->{_type} ne 'pro' ) {
        $channel = 0 ;
        $index   = 0 ;
    }

    print STDERR "get_color " if ( $self->verbose ) ;
    my $bytes = $self->_usb_read( 0x1, 0x0001, 0, 4 ) ;
    my ( $r, $g, $b ) ;

    if ($bytes) {    # first byte may be the id number, followed by the string
        my $ignore ;
        ( $ignore, $r, $g, $b ) = unpack( "CCCC", $bytes ) ;
        if ( $self->inverse ) {
            ( $r, $g, $b ) = ( 255 - $r, 255 - $g, 255 - $b ) ;
        }
    }
    ( $r, $g, $b ) ;
}

# ----------------------------------------------------------------------------

sub _apply_brightness
{
    my $self = shift ;
    my ($c) = @_ ;

    return int( ( $c * $self->brightness ) / 100 ) ;
}

# ----------------------------------------------------------------------------

=item set_color

set the rgb color for a single pixel blinkstick, uses brightness 

=over 4

=item r

red part 0..255

=item g

green part 0..255

=item b

blue part 0..255

=item channel

64 LED block to use

=item index

LED in block to use

=back

returns true/false depending if the mode was set

=cut

sub set_color
{
    my $self = shift ;
    my ( $r, $g, $b, $channel, $index ) = @_ ;

    # make sure values are in range
    $r //= 0 ;
    $g //= 0 ;
    $b //= 0 ;
    ( $r, $g, $b ) = ( $r & 255, $g & 255, $b & 255 ) ;

    if ( $self->inverse ) {
        ( $r, $g, $b ) = ( 255 - $r, 255 - $g, 255 - $b ) ;
    }

    if ( defined $self->{brightness} ) {
        ( $r, $g, $b ) = (
            $self->_apply_brightness($r),
            $self->_apply_brightness($g),
            $self->_apply_brightness($b),
        ) ;
    }

    $channel //= 0 ;
    $index   //= 0 ;

    print STDERR "set_color " if ( $self->verbose ) ;

    if ( $self->type && $self->type eq 'pro' ) {
        # to write to a multi pixel device
        # emulate the write to all, by actually writing to all
        if ( $self->{_mode} == 3 ) {
            for ( my $i = 0; $i < EMULATE_LEDS ; $i++ ) {
                my $block = pack( "CCCCCC", 5, $channel, $i, $r, $g, $b ) ;
                $self->_usb_write( 0x9, 0x0005, 0, $block, length($block) ) ;
                usleep(EMULATE_DELAY_USECS) ;
            }
        } else {
            my $block = pack( "CCCCCC", 5, $channel, $index, $r, $g, $b ) ;
            $self->_usb_write( 0x9, 0x0005, 0, $block, length($block) ) ;
        }
    } else {
        my $block = pack( "CCCC", 0, $r, $g, $b ) ;
        $self->_usb_write( 0x9, 0x0001, 0, $block, length($block) ) ;
    }
}

# ----------------------------------------------------------------------------

=item get_leds

returns the number of leds on the device

=cut

=back

=cut 

sub get_leds
{
    my $self = shift ;
    my $leds ;

    print STDERR "leds " if ( $self->verbose ) ;
    my $bytes = $self->_usb_read( 0x1, 0x81, 0, 2 ) ;
    if ($bytes) {
        my ( $ignore, $l ) = unpack( "CC", $bytes ) ;
        $leds = $l ;
    }

    return $leds || "unknown" ;
}

# ----------------------------------------------------------------------------

=item set_leds

set the number of leds connected to a device

=over 4

=item count

0..64

=back

returns true/false depending if the led count was set

=cut

sub set_leds
{
    my $self = shift ;
    my ($count) = @_ ;

    # make sure values are in range
    print STDERR "set_leds $count " if ( $self->verbose ) ;

    my $block = pack( "CC", 0x81, $count ) ;
    $self->_usb_write( 0x9, 0x81, 0, $block, length($block) ) ;
}


# ----------------------------------------------------------------------------
1 ;

