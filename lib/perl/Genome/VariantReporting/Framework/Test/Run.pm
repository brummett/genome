package Genome::VariantReporting::Framework::Test::Run;

use strict;
use warnings FATAL => 'all';
use Genome;

class Genome::VariantReporting::Framework::Test::Run {
    is => 'Genome::VariantReporting::Framework::Component::Expert::Command',
    has_input => [
        __planned__ => {},
        __provided__ => {
            is_many => 1,
        },
    ],
};

sub name {
    '__test__';
}

sub result_class {
    'Genome::VariantReporting::Framework::Test::RunResult';
}
