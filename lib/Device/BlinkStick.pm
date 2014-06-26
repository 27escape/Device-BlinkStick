
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

=cut

package Device::BlinkStick;

use 5.014;
use warnings;
use strict;
use Moo ;

has basic => ( is => 'ro') ;

# ----------------------------------------------------------------------------
1;

