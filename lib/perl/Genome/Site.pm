package Genome::Site;

use strict;
use warnings;

our $VERSION = $Genome::VERSION;

BEGIN {
    if (my $config = $ENV{GENOME_CONFIG}) {
        # call the specified configuration module;
        eval "use $config";
        die $@ if $@;
    }
    else {
        # look for a config module matching all or part of the hostname 
        use Sys::Hostname;
        my $hostname = Sys::Hostname::hostname();
        my @hwords = map { s/-/_/g; $_ } reverse split('\.',$hostname);
        while (@hwords) {
            my $pkg = 'Genome::Site::' . join("::",@hwords);
            local $SIG{__DIE__};
            local $SIG{__WARN__};
            eval "use $pkg";
            if ($@ =~ /Can't locate/) {
                pop @hwords;
                next;
            }
            elsif ($@) {
                Carp::confess("error in $pkg: $@\n");
            }
            else {
                last;
            }
        }
    }
}

1;

=pod

=head1 NAME

Genome::Site - hostname oriented site-based configuration

=head1 DESCRIPTION

Use the fully-qualified hostname to look up site-based configuration.

=head1 AUTHORS

This software is developed by the analysis and engineering teams at 
The Genome Center at Washington Univiersity in St. Louis, with funding from 
the National Human Genome Research Institute.

=head1 LICENSE

This software is copyright Washington University in St. Louis.  It is released under
the Lesser GNU Public License (LGPL) version 3.  See the associated LICENSE file in
this distribution.

=head1 BUGS

For defects with any software in the genome namespace,
contact genome-dev@genome.wustl.edu.

=cut

