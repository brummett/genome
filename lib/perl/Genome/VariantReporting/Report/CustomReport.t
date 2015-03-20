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
use Genome::VariantReporting::Report::TestHelper qw(test_report_result);

my $pkg = 'Genome::VariantReporting::Report::CustomReport';
use_ok($pkg);

my $data_dir = __FILE__.".d";

my $interpretations = {
    'position' => {
        T => {
            chromosome_name => 1,
            start => 1,
            stop => 1,
            reference => 'A',
            variant => 'T',
        },
        G => {
            chromosome_name => 1,
            start => 1,
            stop => 1,
            reference => 'A',
            variant => 'G',
        },
    },
    'vep' => {
        T => {
            transcript_name   => 'ENST00000452176',
            trv_type          => 'DOWNSTREAM',
            amino_acid_change => '',
            default_gene_name => 'RP5-857K21.5',
            ensembl_gene_id   => 'ENSG00000223659',
        },
        G => {
            transcript_name   => 'ENST00000452176',
            trv_type          => 'DOWNSTREAM',
            amino_acid_change => '',
            default_gene_name => 'RP5-857K22.5',
            ensembl_gene_id   => 'ENSG00000223695',
        },
    },
    'variant-type' => {
        T => {
            variant_type => "snv",
        },
        G => {
            variant_type => "snv",
        },
    },
};

test_report_result(
    data_dir => $data_dir,
    pkg => $pkg,
    interpretations => $interpretations,
);

done_testing;
