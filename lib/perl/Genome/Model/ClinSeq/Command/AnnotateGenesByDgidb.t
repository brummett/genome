#!/usr/bin/env genome-perl

BEGIN { 
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
}

use strict;
use warnings;

use above "Genome";
use Test::More;
use Genome::Utility::Test qw(compare_ok);

my $class = 'Genome::Model::ClinSeq::Command::AnnotateGenesByDgidb';
use_ok($class);

my $column_name = "Gene_name";
my ($in, $in_file) = Genome::Sys->create_temp_file;
$in->print("$column_name\tSomething\n");
$in->print("KRAS\tSomething_else\n");
$in->print("FLT3\tSomething_else\n");
$in->close;

my $reader = Genome::Utility::IO::SeparatedValueReader->create(
    input     => $in_file,
    separator => "\t",
);

my $list = Genome::Model::ClinSeq::Command::AnnotateGenesByDgidb->convert($reader, $column_name);
is($list, "FLT3,KRAS", "List with two items converted correctly");

($in, $in_file) = Genome::Sys->create_temp_file;
$in->print("Not_the_gene_name\tSomething\n");
$in->print("KRAS\tSomething_else\n");
$in->close;

$reader = Genome::Utility::IO::SeparatedValueReader->create(
    input     => $in_file,
    separator => "\t",
);

eval{
    $list = Genome::Model::ClinSeq::Command::AnnotateGenesByDgidb->convert($reader, $column_name)
};

ok($@ =~ /$column_name not found in file/, "Error if the column name does not exist");

($in, $in_file) = Genome::Sys->create_temp_file;
$in->print($column_name."1\tSomething\t".$column_name."2\n");
$in->print("KRAS\tSomething_else\tFLT3\n");
$in->close;

$reader = Genome::Utility::IO::SeparatedValueReader->create(
    input     => $in_file,
    separator => "\t",
);

my $column_regex = '^'.$column_name.'[0-9]';

$list = Genome::Model::ClinSeq::Command::AnnotateGenesByDgidb->convert($reader, $column_regex);
is($list, "FLT3,KRAS", "List with two items converted correctly");

my $test_dir = Genome::Utility::Test->data_dir_ok($class, 'v2') or die "data_dir of $class is not valid\n";
my $test_tsv = $test_dir . '/test.indels.tsv';

my $tmp_dir      = Genome::Sys->create_temp_directory;
my $tmp_test_tsv = $tmp_dir . '/test.indels.tsv';

Genome::Sys->create_symlink($test_tsv, $tmp_test_tsv);

my $cmd = Genome::Model::ClinSeq::Command::AnnotateGenesByDgidb->create(
    input_file      => $tmp_test_tsv,
    gene_name_regex => 'mapped_gene_name',
);

ok($cmd, 'command created ok');
ok($cmd->execute, 'command completed successfully');

my $output_dir = $cmd->output_dir;
is($output_dir, $tmp_test_tsv.'.dgidb', 'output dir named ok');

for my $file_name (qw(all_interactions.tsv expert_antineoplastic.tsv kinase_only.tsv)) {
    my ($output_file, $expected) = map{$_ . "/$file_name"}($output_dir, $test_dir);
    compare_ok($output_file, $expected, 'output file created ok as expected');
}

done_testing;

