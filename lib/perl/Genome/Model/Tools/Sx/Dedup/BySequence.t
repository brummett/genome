#!/usr/bin/env genome-perl

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use strict;
use warnings;

use above 'Genome';

require File::Compare;
use Test::More;

use_ok('Genome::Model::Tools::Sx::Dedup::BySequence') or die;

my $dir = $ENV{GENOME_TEST_INPUTS} . '/Genome-Model-Tools-Sx/DedupBySequence';

my $in_fastq = $dir.'/in.fastq';
ok(-s $in_fastq, 'in fastq');
my $example_fastq = $dir.'/out.fastq';
ok(-s $example_fastq, 'example fastq');

my $tmp_dir = File::Temp::tempdir(CLEANUP => 1);
my $out_fastq = $tmp_dir.'/out.fastq';

my $dedup = Genome::Model::Tools::Sx::Dedup::BySequence->create(
    input  => [ $in_fastq.':cnt=2' ],
    output => [ $out_fastq ],
);
ok($dedup, 'create dedup');
isa_ok($dedup, 'Genome::Model::Tools::Sx::Dedup::BySequence');
ok($dedup->execute, 'execute dedup');
is(File::Compare::compare($example_fastq, $out_fastq), 0, "deduped as expected");

#print "$tmp_dir\n"; <STDIN>;
done_testing();