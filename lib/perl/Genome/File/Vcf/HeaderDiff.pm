package Genome::File::Vcf::HeaderDiff;

use strict;
use warnings FATAL => 'all';
use Params::Validate qw(validate validate_pos :types);

sub new {
    my ($class, $path_a, $diffs_a, $path_b, $diffs_b) = validate_pos(@_,
        {type => SCALAR},
        {type => SCALAR},
        {type => ARRAYREF},
        {type => SCALAR},
        {type => ARRAYREF},
    );
    my $self = {
        _a => $path_a,
        _b => $path_b,
        _diffs_a => $diffs_a,
        _diffs_b => $diffs_b,
    };

    bless $self, $class;
    return $self;
}

sub print {
    my $self = shift;
    _print($self->{_a}, @{$self->{_diffs_a}});   
    _print($self->{_b}, @{$self->{_diffs_b}});   
}


sub _print {
    my $file_name = shift;
    my @lines = @_;

    my $indent = '    ';
    printf "Lines unique to %s are:\n%s%s\n", $file_name, $indent, join("\n$indent", @lines);
}
1;
