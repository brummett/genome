#!/gsc/bin/perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test;

my $class = "Genome::Model::Tools::Annotate::Sv::Dbvar";
use_ok($class);
my $base_dir = Genome::Utility::Test->data_dir($class);
my $version = "1";
my $data_dir = join("/", $base_dir, "v$version");

my $bp_list = {
    17 => [
    {
        chrA => '17',
        bpA => 55687812,
        chrB => '17',
        bpB => 55689917,
        event => 'DEL',
        orient => "+-",
    },
    ],
};

my $expected_output = {
    '17--55687812--17--55689917--DEL' => [
        'ID=esv1834814;Name=esv1834816',
    ],
};

my $annotation_file = $data_dir."/dbvar";

my $cmd = Genome::Model::Tools::Annotate::Sv::Dbvar->create(annotation_file => $annotation_file);
ok($cmd, "Created command");
my $output = $cmd->process_breakpoint_list($bp_list);
ok($output, "Process breakpoint list created output");

is_deeply($output, $expected_output, "Got dbvar") or diag explain [$output, $expected_output]; 

done_testing;
