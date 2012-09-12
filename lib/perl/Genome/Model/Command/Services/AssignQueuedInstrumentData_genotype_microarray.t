#!/usr/bin/env genome-perl

use strict;
use warnings;

BEGIN {
    $ENV{UR_DBI_NO_COMMIT} = 1;
    $ENV{UR_USE_DUMMY_AUTOGENERATED_IDS} = 1;
    $ENV{UR_COMMAND_DUMP_STATUS_MESSAGES} = 1;
}

use above 'Genome';

use Test::MockObject;
use Test::More;

use_ok('Genome::Model::Command::Services::AssignQueuedInstrumentData') or die;

my $qidfgm_cnt = 0;
my $sample_cnt = 0;
my (@samples, @instrument_data, @pses, @pse_params);
no warnings;
*Genome::InstrumentDataAttribute::get = sub {
    my ($class, %params) = @_;
    my %attrs = map { $_->id => $_ } map { $_->attributes } @instrument_data;
    for my $param_key ( keys %params ) {
        my @param_values = ( ref $params{$param_key} ? @{$params{$param_key}} : $params{$param_key} );
        my @unmatched_attrs;
        for my $attr ( values %attrs ) {
            next if grep { $attr->$param_key eq $_ } @param_values;
            push @unmatched_attrs, $attr->id;
        }
        for ( @unmatched_attrs ) { delete $attrs{$_} }
    }
    return values %attrs;
};
sub GSC::PSE::get { return grep { not $_->can('completed') } @pses; }
use warnings;

my $source = Genome::Individual->__define__(
    name => '__TEST_HUMAN1_SOURCE__', 
    taxon => Genome::Taxon->__define__(name => 'human', domain => 'Eukaryota', species_latin_name => 'H. sapiens'),
);
ok($source, 'define source');
ok($source->taxon, 'define source taxon');
ok(_qidfgm($source), 'create qidfgm for bacteria taxon');
is(@instrument_data, $qidfgm_cnt, "create $qidfgm_cnt inst data");
is_deeply(
    [ map { $_->attribute_value } map { $_->attributes(attribute_label => 'tgi_lims_status') } @instrument_data ],
    [ map { 'new' } @instrument_data ],
    'set tgi lims status to new',
);
is(@pses, $qidfgm_cnt, "create $qidfgm_cnt pses");

my $cmd = Genome::Model::Command::Services::AssignQueuedInstrumentData->create;
ok($cmd, 'create aqid');
ok($cmd->execute, 'execute');
my @new_models = values %{$cmd->_newly_created_models};
my %new_models = _model_hash(@new_models);
#print Data::Dumper::Dumper(\%new_models);
is_deeply(
    \%new_models,
    {
        "AQID-testsample1.human.prod-microarray.wugc.infinium.NCBI-human-build36" => {
            subject => $samples[0]->name,
            processing_profile_id => 2575175,
            inst => [ $instrument_data[0]->id ],
            auto_assign_inst_data => 0,
        },
        "AQID-testsample1.human.prod-microarray.wugc.infinium.GRCh37-lite-build37" => {
            subject => $samples[0]->name,
            processing_profile_id => 2575175,
            inst => [ $instrument_data[0]->id ],
            auto_assign_inst_data => 0,
        },
    },
    'new models',
);
is_deeply(
    [ map { $_->attribute_value } map { $_->attributes(attribute_label => 'tgi_lims_status') } @instrument_data ],
    [ map { 'processed' } @instrument_data ],
    'set tgi lims status to processed',
);
is_deeply(
    [ map { $_->attribute_value } map { $_->attributes(attribute_label => 'tgi_lims_status') } @instrument_data ],
    [ map { 'processed' } @instrument_data ],
    'set tgi lims status to processed for all instrument data',
);

done_testing();
exit;

sub _qidfgm {
    my $source = shift;
    $qidfgm_cnt++;
    $sample_cnt++;
    my $sample = Genome::Sample->__define__(
        name => 'AQID-testsample'.$sample_cnt.'.'.lc($source->taxon->name),
        source => $source,
        extraction_type => 'genomic',
    );
    ok($sample, 'sample '.$sample_cnt);
    push @samples, $sample;
    my $library = Genome::Library->__define__(
        name => $sample->name.'-testlib',
        sample_id => $sample->id,
    );
    ok($library, 'create library '.$qidfgm_cnt);

    my $instrument_data = Genome::InstrumentData::Imported->__define__(
        library_id => $library->id,
        sequencing_platform => 'infinium',
        import_format => 'genotype file',
        import_source_name => 'wugc',
    );
    ok($instrument_data, 'created instrument data '.$qidfgm_cnt);
    push @instrument_data, $instrument_data;
    $instrument_data->add_attribute(
        attribute_label => 'tgi_lims_status',
        attribute_value => 'new',
    );

    my $pse = Test::MockObject->new();
    $pse->set_always(id => $qidfgm_cnt - 10000);
    $pse->set_always(pse_id => $qidfgm_cnt - 10000);
    $pse->set_always(ps_id => 3733);
    $pse->set_always(ei_id => '464681');
    $pse->mock(pse_status => sub{ $pse->set_true('completed'); });
    ok($pse, 'create pse '.$qidfgm_cnt);
    my %params = (
        instrument_data_type => 'genotyper results',
        instrument_data_id => $instrument_data->id,
        subject_class_name => 'Genome::Sample',
        subject_id => $sample->id,
    );
    $pse->mock(
        add_param => sub{
            my ($pse, $key, $value) = @_;
            my $param = Test::MockObject->new();
            push @pse_params, $param;
            $param->set_always(pse_id => $pse->id);
            $param->set_always(param_name => $key);
            $param->set_always(param_value => $value);
            return $param;
        }
    );
    for my $key ( keys %params ) {
        $pse->add_param($key, $params{$key});
    }
    $pse->mock(
        added_param => sub{
            my ($pse, $key) = @_;
            for my $param ( @pse_params ) {
                return $param->param_value if $param->pse_id == $pse->id and $param->param_name eq $key;
            }
            return;
        }
    );
    $pse->mock(
        add_reference_sequence_build_param_for_processing_profile => sub{
            my ($self, $pp, $refseq) = @_;
            return $self->add_param('refseq_build_id_for_'.$pp->id, $refseq->id);
        },
    );
    $pse->mock(
        reference_sequence_build_param_for_processing_profile => sub{
            my ($self, $pp) = @_;
            return $self->added_param('refseq_build_id_for_'.$pp->id);
        },
    );
    push @pses, $pse;
    return 1;
}

sub _model_hash {
    return map { 
        $_->name => { 
            subject => $_->subject_name, 
            processing_profile_id => $_->processing_profile_id,
            inst => [ map { $_->id } $_->instrument_data ],
            auto_assign_inst_data => $_->auto_assign_inst_data,
        }
    } @_;
}

