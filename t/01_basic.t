
#!/usr/bin/perl -w

=head1 NAME

01_basic.t

=head1 DESCRIPTION

test module Device::BlinkStick

=head1 AUTHOR

kevin mulholland, moodfarm@cpan.org

=cut

use v5.10;
use strict;
use warnings;
use Test::More tests => 2;

BEGIN { use_ok('Device::BlinkStick'); }

SKIP: {

    if ( $ENV{AUTHOR_TESTING} ) {

        # these tests need a blink stick to be attached
        subtest 'authors_own' => sub {
            my $stick = Device::BlinkStick->new();
            my $info  = $stick->info();
            ok( $info->{serial},       "has a serial number" );
            ok( $info->{manufacturer}, "has a manufacturer" );
            ok( $info->{product},      "has a product" );
            ok( $info->{info1},        "has a infoblock 1" );
            ok( $info->{info2},        "has a infoblock 2" );

            my ( $r, $g, $b ) = $stick->get_color();
            ok( defined $r && defined $g && defined $b, "has a color" );

            my $info2 = "test $$";
            $stick->set_info_block2($info2);
            ok( $info2 eq $stick->get_info_block2(), "set infoblock 2" );

            $stick->set_color( 0, 0,   0 );
            $stick->set_color( 0, 255, 0 );
            ( $r, $g, $b ) = $stick->get_color();
            ok( "$r-$g-$b" eq '0-255-0', "set color green" );
            $stick->set_color( 0, 0, 0 );
        }
    }
    else {
        skip "Author testing", 1;
    }
}
