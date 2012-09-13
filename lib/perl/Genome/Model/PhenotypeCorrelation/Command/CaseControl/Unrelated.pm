package Genome::Model::PhenotypeCorrelation::Command::CaseControl::Unrelated;

use strict;
use warnings;

use Carp 'confess';
use Genome;
use Workflow;
use Workflow::Simple;

class Genome::Model::PhenotypeCorrelation::Command::CaseControl::Unrelated {
    is  => 'Command',
    has_input => [
        multisample_vcf => {
            is => "String",
            doc => 'File of variants to analyze',
        },
        sample_list_file => {
            is => "String",
            doc => 'File containing samples names, 1 per line, for input into MuSiC',
        },
        clinical_data_file => {
            is => "String",
            doc => 'File containing clinical data',
        },
        glm_model_file => {
            is => "String",
            doc => 'File containing the model specification for this analysis',
        },
        output_directory => {
            is => "String",
            doc => 'Where to place output files',
        },
        glm_max_cols_per_file => {
            is => "Number",
            doc => "Max number of columns per variant matrix for parallel clinical correlation",
            default_value => 5000,
            is_optional => 1,
        },
        maximum_maf => {
            is => "Number",
            doc => "Maximum minor allele frequency cutoff to include in burden tests",
            default_value => 0.01,
        },
        identify_cases_by => {
            is => 'Text',
            doc => 'the expression which matches "case" samples, typically by their attributes',
            is_optional => 1,
        },
        identify_controls_by => {
            is => 'Text',
            doc => 'the expression which matches "control" samples, typically by their attributes',
            is_optional => 1,
        },
    ],
};

sub help_synopsis {
    return <<"EOS"
EOS
}

sub help_detail {
    return <<"EOS"
Need documenation here.
EOS
}

sub _create_workflow {
    my $self = shift;
    my $multisample_vcf = $self->multisample_vcf;
    my $clinical_data = $self->clinical_data_file;
    my $glm_model_file = $self->glm_model_file;
    my $sample_list = $self->sample_list_file;
    my $output_directory = $self->output_directory;
    my $single_mutation_matrix = "$output_directory/variant_matrix.txt";
    my $clinical_correlation_output_prefix = "$output_directory/clinical_correlation_result";

    my $clinical_correlation_glm_output = "$output_directory/clinical_correlation_result.glm.csv";
    my $clinical_correlation_glm_qqplot = $clinical_correlation_glm_output . ".qqplot";

    my $clinical_correlation_categorical_output = "$output_directory/clinical_correlation_result.categorical.csv";
    my $clinical_correlation_categorical_qqplot = $clinical_correlation_categorical_output . ".qqplot";

    my $clinical_data_summary_dir = "$output_directory/clinical_data_summary";

    my $vep_annotation_file_path = "$multisample_vcf.VEP_annotated";
    my $sorted_vep = $vep_annotation_file_path . ".sorted";
    my $burden_matrix_file = "$output_directory/burden_matrix.txt";
    my $vep_burden_file = "$vep_annotation_file_path.for_burden";
    my $burden_test_output_directory = "$output_directory/burden_analysis";

    for my $p ($burden_test_output_directory, $clinical_data_summary_dir) {
        unless(Genome::Sys->create_directory($p)) {
            die $self->error_message("Unable to create an output directory $p");
        }
    }

    my %workflow_data = (
        # Create clinical data summary
        cds => {
            name => "Create clinical data summary",
            class => "Genome::Model::PhenotypeCorrelation::Command::ClinicalDataSummary",
            inputs => {
                glm_model_file => $glm_model_file,
                clinical_data_file => $clinical_data,
                output_directory => $clinical_data_summary_dir,
                include_boxplots => 1,
            },
            inputs_from => {},
        },

        # Create single variant matrix
        svm => {
            name => "Create variant matrix for single variant test",
            class => "Genome::Model::Tools::Vcf::VcfToVariantMatrix",
            inputs => {
                vcf_file => $multisample_vcf,
                output_file => $single_mutation_matrix,
                matrix_genotype_version => 'Bases',
                transpose => 1,
            },
            inputs_from => {},
        },

        # Run parallel clinical correlation
        pcc => {
            name => "Parallel clinical correlation",
            class => "Genome::Model::PhenotypeCorrelation::Command::ParallelClinicalCorrelation",
            inputs => {
                sample_list_file => $sample_list,
                work_directory => $output_directory,
                output_prefix => $clinical_correlation_output_prefix,
                glm_model_file => $glm_model_file,
                clinical_data_file => $clinical_data,
                max_cols_per_file => $self->glm_max_cols_per_file,
            },
            inputs_from => {
                svm => {
                    output_file => "variant_matrix",
                }
            },
        },

        # Create glm QQ plot
        qqp_glm => {
            name => "GLM QQ plot generation",
            class => "Genome::Model::Tools::Germline::Qqplot",
            inputs => {
                output_file_basename => $clinical_correlation_glm_qqplot,
                header => 1,
                separator => "\t",
                pvalue_column => "p.value",
                title => "Quantile-quantile plot of p-values from glm",
                image_type => "png",
            },
            inputs_from => {
                "pcc" => {
                    glm_output_file => "input_file",
                },
            },
        },


        # Create categorical QQ plot
        qqp_categorical => {
            name => "Categorical QQ plot generation",
            class => "Genome::Model::Tools::Germline::Qqplot",
            inputs => {
                output_file_basename => $clinical_correlation_categorical_qqplot,
                header => 1,
                separator => ",",
                pvalue_column => "p",
                title => "Quantile-quantile plot of p-values from FET",
                image_type => "png",
            },
            inputs_from => {
                "pcc" => {
                    categorical_output_file => "input_file",
                },
            },
        },

        # Run VEP
        vep => {
            name => "VEP annotation",
            class => "Genome::Db::Ensembl::Vep",
            inputs => {
                input_file => $multisample_vcf,
                output_file => $vep_annotation_file_path,
                format => "vcf",
                condel => "b",
                polyphen => "b",
                sift => "b",
                hgnc => 1,
            },
            inputs_from => {
            },
        },

        # Sort VEP output
        svep => {
            name => "Sort VEP annotation",
            class => "Genome::Model::PhenotypeCorrelation::Command::SortVepOutput",
            inputs => {
                output_file => $sorted_vep,
            },
            inputs_from => {
                vep => {
                    output_file => "input_file",
                },
            },
        },

        # Create burden variant matrix
        bvm => {
            name => "Create variant matrix for burden analysis",
            class => "Genome::Model::Tools::Vcf::VcfToBurdenMatrix",
            inputs => {
                vcf_file => $multisample_vcf,
                output_file => $burden_matrix_file,
                burden_test_annotation_file => $vep_burden_file,
                transpose => 0,
            },
            inputs_from => {
                svep => {
                    output_file => "vep_annotation_file",
                }
            },
        },

        # Run burden test
        bur => {
            name => "Burden analysis",
            class => "Genome::Model::Tools::Germline::BurdenAnalysis",
            inputs => {
                glm_clinical_data_file => $clinical_data,
                output_directory => $burden_test_output_directory,
                glm_model_file => $glm_model_file,
                base_R_commands => '/gscuser/qzhang/gstat/burdentest/burdentest.R',
                maf_cutoff => $self->maximum_maf,
                permutations => "1",
                trv_types => "ALL",
                p_value_permutations => 1,  #not a general case desirable
                use_bsub => 1,
                aggregate_only => 0,
            },
            inputs_from => {
                bvm => {
                    output_file => "mutation_file",
                    burden_test_annotation_file => "VEP_annotation_file",
                },
            },
        },
    );

    # Figure out the input/output names
    my %inputs;
    my @outputs;
    for my $opname (keys %workflow_data) {
        my $node = $workflow_data{$opname};
        my $inputs_hash = $node->{inputs};

        for my $input_name (keys %$inputs_hash) {
            my $full_name = "${opname}_$input_name";
            $inputs{$full_name} = $inputs_hash->{$input_name};
        }
        push(@outputs, "${opname}_result");
    }

    my $workflow = Workflow::Model->create(
        name => "PhenotypeCorrelation unrelated case/control",
        input_properties => [keys %inputs],
        output_properties => \@outputs,
    );

    # create operations
    my %ops;
    for my $opname (keys %workflow_data) {
        my $node = $workflow_data{$opname};
        $ops{$opname} = $workflow->add_operation(
            name => $node->{name},
            operation_type => Workflow::OperationType::Command->get($node->{class}),
        );
    }

    # add workflow links
    for my $opname (keys %workflow_data) {
        my $node = $workflow_data{$opname};
        my $op = $ops{$opname};

        # connect inputs from workflow input connector
        my $inputs_hash = $node->{inputs};
        for my $input_name (keys %$inputs_hash) {
            my $full_name = "${opname}_$input_name";
            $workflow->add_link(
                left_operation => $workflow->get_input_connector,
                left_property => $full_name,
                right_operation => $op,
                right_property => $input_name,
            );
        }

        # connect result of each operation to outputs
        $workflow->add_link(
            left_operation => $op,
            left_property => "result",
            right_operation => $workflow->get_output_connector,
            right_property => "${opname}_result",
        );

        # connect inputs between nodes
        for my $source_op_name (keys %{$node->{inputs_from}}) {
            my $source_op = $ops{$source_op_name};
            my $source_prop_hash = $node->{inputs_from}->{$source_op_name};
            for my $source_prop_name (keys %$source_prop_hash) {
                my $target_prop_name = $source_prop_hash->{$source_prop_name};
                $workflow->add_link(
                    left_operation => $source_op,
                    left_property => $source_prop_name,
                    right_operation => $op,
                    right_property => $target_prop_name,
                );
            }
        }

    }
    $workflow->log_dir("$output_directory/logs");

    return $workflow, %inputs;
}

# Binary traits may need to be coerced into 0/1 encoding
sub update_clinical_data {
    my $self = shift;
    my $cdata_file = $self->clinical_data_file;
    $self->status_message("Checking clinical data file $cdata_file...");
    my $cdata_md5_file = "$cdata_file.md5";
    my $cdata = Genome::Model::PhenotypeCorrelation::ClinicalData->from_file($cdata_file);
    my $glm_file = $self->glm_model_file;
    my $glm_model = Genome::Model::PhenotypeCorrelation::GlmConfig->from_file($glm_file);
    my @binary_attrs = $glm_model->categorical_attributes;
    my $n_binary_attrs = scalar(@binary_attrs);
    if (@binary_attrs != 1) {
        my $names = join(", ", map {$_->{attr_name}} @binary_attrs);
        confess "Found $n_binary_attrs binary attributes ($names) in glm config $glm_file, expected 1";
    }
    my $attr_name = $binary_attrs[0]->{attr_name};
    my %updates = $cdata->convert_attr_to_factor($attr_name,
        levels => [$self->identify_controls_by, $self->identify_cases_by]
        );
    if (%updates) {
        $self->status_message("The encoding of attribute $attr_name has changed:\n\t"
            . join("\n\t", map { $_ . " => " . $updates{$_} } keys %updates )
            );
        my $orig_cdata_file = "$cdata_file.orig";
        my $orig_cdata_md5_file = "$cdata_md5_file.orig";
        rename($cdata_file, $orig_cdata_file);
        rename($cdata_md5_file, $orig_cdata_md5_file) if -e $cdata_md5_file;
        my $md5 = $cdata->to_file($cdata_file);
        my $md5_fh = Genome::Sys->open_file_for_writing($cdata_md5_file);
        $md5_fh->write("$md5\n");
        $md5_fh->close();
    }
}

sub execute {
    my $self = shift;
    $self->update_clinical_data();

    my ($workflow, %inputs) = $self->_create_workflow();
    my $workflow_xml_file = $self->output_directory . "/workflow.xml";

    my $xml = $workflow->save_to_xml;
    my $xml_file = Genome::Sys->open_file_for_writing($workflow_xml_file);
    print $xml_file $xml;
    $xml_file->close;

    my $result = Workflow::Simple::run_workflow_lsf($workflow, %inputs);
    unless ($result) {
        $self->error_message( join("\n", map($_->name . ': ' . $_->error, @Workflow::Simple::ERROR)) );
        die $self->error_message("Unrelated case control workflow did not return correctly.");
    }

    return 1;
}

1;
