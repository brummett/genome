package Genome::Sample::Command::Import::Base;

use strict;
use warnings;

use Genome;

class Genome::Sample::Command::Import::Base {
    is => 'Command::V2',
    is_abstract => 1,
    doc => 'Import samples from known sources',
    has => [
        name => {
            is => 'Text',
            doc => 'Sample name. Source name will be derived from the sample name. The typical format is "NOMENCLATURE-SOURCE_ID/NAME-SAMPLE_ID/NAME, but may vary based on source.',
        },
        extraction_type => {
            is => 'Text',
            default_value => 'genomic dna',
            valid_values => [ 'cdna', 'genomic dna', 'ipr product', 'rna', 'total rna', ],
            doc => 'The extraction type of the sample.',
        },
    ],
    has_optional => [
        individual_attributes => {
            is => 'Text',
            is_many => 1,
            doc => 'Additional attributes to add to the individual. Give as key value pairs. Separate key and value with an equals (=) and pairs with a comma (,). Ex: attr1=val1,attr2=val2',
        },
        sample_attributes => {
            is => 'Text',
            is_many => 1,
            doc => 'Additional attributes to add to the sample. Give as key value pairs. Separate key and value with an equals (=) and pairs with a comma (,). Ex: attr1=val1,attr2=val2',
        },
        library_attributes => {
            is => 'Text',
            is_many => 1,
            doc => 'Additional attributes to add to the library. Give as key value pairs. Separate key and value with an equals (=) and pairs with a comma (,). Ex: attr1=val1,attr2=val2',
        },
    ],
    has_optional_transient => [
        # taxon
        _taxon => { is => 'Genome::Taxon', is_optional => 1, },
        # source
        _individual => { is => 'Genome::Individual', is_optional => 1, },
        _individual_name => { is => 'Text', },
        _individual_attributes => { is => 'Hash', },
        # sample
        _sample => { is => 'Genome::Sample', is_optional => 1, },
        _sample_attributes => { is => 'Hash', },
        # library
        _library => { is => 'Genome::Library', is_optional => 1, },
        _library_attributes => { is => 'Hash', },
        # misc
        _minimum_unique_source_name_parts => { is => 'Number', default_value => 2, },
    ],
};

sub help_detail {
    return;
}

sub execute {
    my $self = shift;
    $self->status_message('Import '.$self->nomenclature.' sample...');

    my $individual_name_ok = $self->_validate_name_and_set_individual_name;
    return if not $individual_name_ok;

    my $resolve_attrs_ok = $self->_resolve_incoming_attributes;
    return if not $resolve_attrs_ok;

    my $import = $self->_import;
    return if not $import;

    $self->status_message('Import sample...OK');
    return 1;
}

sub _resolve_incoming_attributes {
    my $self = shift;

    for my $type (qw/ individual sample library /) {
        my $method = '_resolve_'.$type.'_attributes';
        my $resolve_attrs_ok = $self->$method;
        return if not $resolve_attrs_ok;
    }

    return 1;
}

sub _import {
    my $self = shift;

    my $taxon_name = $self->taxon_name;
    my $individual_params = $self->_individual_attributes;
    my $individual_upn = $individual_params->{upn};
    Carp::confess('No individual upn in individual params given to import') if not $individual_upn;
    my $sample_params = $self->_sample_attributes;
    my $sample_name = $sample_params->{name};
    Carp::confess('No sample name in sample params given to import') if not $sample_name;
    my $library_params = $self->_library_attributes;
    my $library_ext = delete $library_params->{ext};
    Carp::confess('No library ext given to import') if not $library_ext;

    # taxon
    $self->_taxon( Genome::Taxon->get(name => $taxon_name) );
    Carp::confess("Cannot get taxon for '$taxon_name'") if not $self->_taxon;
    $self->status_message('Found taxon: '.$self->_taxon->__display_name__);

    # sample
    my $sample = Genome::Sample->get(name => $sample_name);
    if ( $sample ) {
        $self->_sample($sample);
        $self->status_message('Found sample: '.join(' ', map{ $sample->$_ } (qw/ id name/)));
    }
    else { # create, set individual later
        $sample = $self->_create_sample;
        return if not $sample;
    }

    # individual
    my $individual = $self->_get_individual($individual_upn); # get by sample and upn
    if ( not $individual ) {
        $individual = $self->_create_individual;
        return if not $individual;
    }
    else {
        $self->status_message('Found individual: '.join(' ', map{ $individual->$_ } (qw/ id name upn /)));
        $self->status_message("Found individual 'upn' (".$self->_individual->upn.") does not match the upn given ($individual_upn). This is probably ok.") if $individual->upn ne $individual_upn;
    }

    if ( not $sample->source_id ) {
        $sample->source_id( $individual->id );
    }
    if ( $sample->source_id ne $individual->id ) {
        $self->error_message('Sample ('.$sample->id.') source id ('.$sample->source_id.') does not match found individual ('.$individual->id.')');
        return;
    }

    if ( not $sample->source_type ) {
        $sample->source_type( $individual->subject_type );
    }
    if ( $sample->source_id ne $individual->id ) {
        $self->error_message('Sample ('.$sample->id.') source type ('.$sample->source_type.') does not match individual ('.$individual->subject_type.')');
        return;
    }

    # library
    my $library = $self->_get_or_create_library_for_extension($library_ext);
    $library = $self->_set_library_params($library);
    return if not $library;

    return 1;
}

sub _set_library_params {
    my $self = shift;
    my $library = shift;

    my $params = $self->_library_attributes;
    for my $param_name (keys %{$params}) {
        $library->$param_name($params->{$param_name});
    }
    return $library;
}

sub _validate_name_and_set_individual_name {
    my $self = shift;
    $self->status_message('Validate sample name and resolve individual name...');

    my $name_regexp = $self->name_regexp;
    my $name = $self->name;
    $self->status_message('Sample name: '.$name);
    $self->status_message('Sample regexp: '.$name_regexp);
    if ( $name !~ /$name_regexp/ ) {
        $self->error_message("Name ($name) is invalid!");
        return;
    }
    my $individual_name = $1;
    $self->status_message('Individual name: '.$individual_name);
    $self->_individual_name($individual_name);

    $self->status_message('Validate sample name and resolve individual name...done');
    return 1
}

sub _get_individual {
    my ($self, $upn) = @_;

    my $sample = $self->_sample;
    Carp::confess('No sample set to get individual') if not $sample;
    Carp::confess('No "upn" given to get individual') if not $upn;

    if ( my $individual = $sample->source ) {
        return $self->_individual($individual);
    }

    my %individuals_from_similar_samples;
    my @tokens = split('-', $sample->name);
    my $min_unique_name_parts = $self->_minimum_unique_source_name_parts - 1;
    for ( my $i = $#tokens - 1; $i > $min_unique_name_parts; $i--  ) { # go down to 2 levels
        my $extraction_label = join('-', @tokens[0..$i]);
        my @samples = Genome::Sample->get('extraction_label like' => $extraction_label.'%');
        for my $sample ( @samples ) {
            my $source = $sample->source;
            next if not $source;
            next if not $source->isa('Genome::Individual');
            $individuals_from_similar_samples{$source->id} = $source;
        }
        last if %individuals_from_similar_samples;
    }

    if ( %individuals_from_similar_samples ) {
        my %individuals = map { $_->id => $_ } values %individuals_from_similar_samples;
        if ( keys %individuals > 1 ) {
            $self->error_message("Found multiple individuals for similar samples: ".join(' ', keys %individuals));
            return;
        }
        my ($individual) = values %individuals;
        return $self->_individual($individual);
    }

    my $individual_for_given_upn = Genome::Individual->get(upn => $upn);
    return if not $individual_for_given_upn;
    return $self->_individual($individual_for_given_upn);
}

sub _create_individual {
    my $self = shift;

    my %params = %{$self->_individual_attributes};
    Carp::confess('No "upn" given to create individual') if not $params{upn};
    Carp::confess('No "nomenclature" given to create individual') if not $params{nomenclature};
    Carp::confess('No taxon set to create individual') if not $self->_taxon;

    $params{name} = $params{upn} if not $params{name};
    $params{taxon} = $self->_taxon;
    $params{gender} = 'unspecified' if not $params{gender};

    $self->status_message('Create individual...');
    $self->status_message('Individual params: '._display_string_for_params(\%params));
    my $transaction = UR::Context::Transaction->begin();
    my $individual = Genome::Individual->create(%params);
    if ( not defined $individual ) {
        $self->error_message('Could not create individual');
        return;
    }

    $self->status_message('Create individual: '.join(' ', map{ $individual->$_ } (qw/ id name/)));
    return $self->_individual($individual);
}

sub _create_sample {
    my $self = shift;

    my %params = %{$self->_sample_attributes};
    Carp::confess('No name given to create sample') if not $params{name};
    Carp::confess('No nomenclature set to create sample') if not $params{nomenclature};

    if ( $self->_individual ) {
        $params{source_id} = $self->_individual->id;
        $params{source_type} = $self->_individual->subject_type;
    }

    $self->status_message('Create sample...');
    $self->status_message('Sample params: '._display_string_for_params(\%params));
    my $sample = Genome::Sample->create(%params);
    if ( not defined $sample ) {
        $self->error_message('Cannot create sample');
        return;
    }

    $self->status_message('Create sample: '.join(' ', map { $sample->$_ } (qw/ id name /)));
    return $self->_sample($sample);
}

sub _get_or_create_library_for_extension {
    my ($self, $ext) = @_;

    my $library = $self->_get_library_for_extension($ext);
    return $library if $library;

    return $self->_create_library_for_extension($ext);
}

sub _get_library_name_for_extension {
    my ($self, $ext) = @_;

    Carp::confess('No sample set to get or create library') if not $self->_sample;
    Carp::confess('No library extension') if not defined $ext;
    my @valid_exts = (qw/ extlibs microarraylib /);
    Carp::confess("Invalid library extension ($ext). Valid extentions: ".join(' ', @valid_exts)) if not grep { $ext eq $_ } @valid_exts;

    return $self->_sample->name.'-'.$ext;
}

sub _get_library_for_extension {
    my ($self, $ext) = @_;

    my $name = $self->_get_library_name_for_extension($ext); # confess on error
    my $library = Genome::Library->get(name => $name);
    return if not $library;

    $self->status_message('Found library: '.join(' ', map{ $library->$_ } (qw/ id name/)));

    return $self->_library($library);

}

sub _create_library_for_extension {
    my ($self, $ext) = @_;

    my %params = (
        name => $self->_get_library_name_for_extension($ext), # confess on error
        sample_id => $self->_sample->id,
    );

    $self->status_message('Create library...');
    $self->status_message('Library params: '._display_string_for_params(\%params));
    my $library = Genome::Library->create(%params);
    if ( not $library ) {
        $self->error_message('Cannot not create library to import sample');
        return;
    }

    $self->status_message('Create library: '.join(' ', map{ $library->$_ } (qw/ id name/)));
    return $self->_library($library);
}

sub _display_string_for_params {
    my ($params) = shift;

    my $string = "\n";
    for my $key ( sort keys %$params ) {
        $string .= sprintf(" %s: %s\n", $key, ( ref($params->{$key}) ? $params->{$key}->__display_name__ : $params->{$key} ));
    }

    return $string;
}

sub _resolve_individual_attributes {
    my $self = shift;
    my %attributes = (
        nomenclature => $self->nomenclature,
        name => $self->_individual_name,
        upn => $self->_individual_name,
    );
    return if not $self->_resolve_attributes('individual', \%attributes);
    $self->_individual_attributes(\%attributes);
    return 1;
}

sub _resolve_sample_attributes {
    my $self = shift;
    my %attributes = (
        nomenclature => $self->nomenclature,
        name => $self->name,
        extraction_label => $self->name,
    );
    return if not $self->_resolve_attributes('sample', \%attributes);
    $attributes{extraction_type} = $self->extraction_type if not defined $attributes{extraction_type};
    $self->_sample_attributes(\%attributes);
    return 1;
}

sub _resolve_library_attributes {
    my $self = shift;
    my %attributes = (
        ext => "extlibs",
    );
    return if not $self->_resolve_attributes('library', \%attributes);
    $self->_library_attributes(\%attributes);
    return 1;
}

sub _resolve_attributes {
    my ($self, $type, $attributes) = @_;

    my $attributes_method = $type.'_attributes';
    my @additional_attributes = $self->$attributes_method;
    if ( @additional_attributes ) {
        no warnings;
        my %additional_attributes = map { split('=') } @additional_attributes;
        use warnings;

        for my $label ( keys %additional_attributes ) {
            if ( defined $additional_attributes{$label} ) {
                $attributes->{$label} = $additional_attributes{$label};
            }
            else {
                $self->error_message(ucfirst($type)." attribute label ($label) does not have a value!");
                return;
            }
        }
    }

    my $attribute_names_method = '_'.$type.'_attribute_names';
    my $names = eval{ $self->$attribute_names_method; };
    for my $name ( @$names ) {
        my $value = eval{ $self->$name; };
        if ( $@ ) {
            $self->error_message($@);
            return;
        }
        next if not defined $value;
        $name =~ s/^$type\_//; # attributes may have the same name, like common_name, so remove the type in front
        $attributes->{$name} = $value;
    }

    return 1;
}

1;

