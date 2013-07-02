package Genome::InstrumentData::Command::Import::WorkFlow::Helpers;

use strict;
use warnings;

use Genome;

require Carp;
require File::Copy;
require Filesys::Df;

class Genome::InstrumentData::Command::Import::WorkFlow::Helpers { 
    is => 'UR::Singleton',
};

#<INST DATA INFO>#
sub local_source_files_for_instrument_data {
    my ($self, $instrument_data) = @_;

    Carp::confess('No instrument data to get local source files!') if not $instrument_data;

    my $directory = $instrument_data->data_directory;
    Carp::confess('No instrument data directory to get local source files!') if not $directory;

    my @local_source_files;
    for my $source_file ( split(',', $instrument_data->original_data_path) ) {
        my $source_file_basename = File::Basename::basename($source_file);
        $source_file_basename =~ s/\.gz$//;
        push @local_source_files, $directory.'/'.$source_file_basename;
    }

    return @local_source_files;
}
#<>#

#<WORKFLOW>#
sub add_operation_to_workflow {
    my ($self, $workflow, $name) = @_;

    my $command_class_name = 'Genome::InstrumentData::Command::Import::WorkFlow::'.join('', map { ucfirst } split(' ', $name));
    my $operation_type = Workflow::OperationType::Command->create(command_class_name => $command_class_name);
    if ( not $operation_type ) {
        $self->error_message("Failed to create work flow operation for $name");
        return;
    }

    my $operation = $workflow->add_operation(
        name => $name,
        operation_type => $operation_type,
    );

    return $operation;
}
#<>#

#<MOVE>#
sub move_file {
    my ($self, $from, $to) = @_;

    $self->status_message('Move file...');
    my $from_sz = -s $from;
    $self->status_message("From: $from");
    $self->status_message("To: $to");
    my $move_ok = File::Copy::move($from, $to);
    if ( not $move_ok ) {
        $self->error_message('Move failed!');
        return;
    }
    my $to_sz = -s $to;
    if ( not $to_sz or $to_sz != $from_sz ) {
        $self->error_message("Move succeeded, but destination size is diffeerent from original! $to_sz vs $from_sz");
        return;
    }

    $self->status_message('Move file...done');
    return 1;
}
#<>#

#<FILE SIZE>#
sub kilobytes_needed_for_processing_of_source_files {
    my ($self, @source_files) = @_;

    Carp::confess('No source files to get kb needed!') if not @source_files;

    my $kb_needed = 0;
    for my $source_file ( @source_files ) {
        my $size = $self->size_of_source_file($source_file);
        return if not $size;
        $size *= 3 if $source_file =~ /\.gz$/; # assume ~30% compression rate for gzipped fasta/q
        $kb_needed += int($size / 1024) + 1;
    }

    $kb_needed *= 3; # reserve 3X for processing

    return $kb_needed;
}

sub size_of_source_file {
    my ($self, $source_file) = @_;

    Carp::confess('No source file to get size!') if not $source_file;

    my $size;
    if ( $source_file =~ /^http/ ) {
        $size = $self->size_of_remote_file($source_file);
    }
    else {
        $size = -s $source_file;
    }

    if ( not $size ) {
        $self->error_message('Source file does have any size! '.$source_file);
        return;
    }

    return $size;
}

sub size_of_remote_file {
    my ($self, $remote_file) = @_;

    Carp::confess('No remote file to get size in kb!') if not $remote_file;

    my $fh = IO::File->new("wget --spider $remote_file |");
    my ($size, $exists);
    while ( my $line = $fh->getline ) {
        chomp $line;
        if ( $line =~ /^Length: (\d+) / ) {
            $size = $1;
        }
        elsif ( $line eq 'Remote file exists.' ) {
            $exists = 1;
        }
    }

    if ( not $exists ){
        $self->error_message('Remote file does not exist! '.$remote_file);
        return;
    }

    if ( not $size ){
        $self->error_message('Remote file does have any size! '.$remote_file);
        return;
    }

    return $size;
}

sub verify_adequate_disk_space_is_available_for_source_files {
    my ($self, %params) = @_;
    $self->status_message('Verify adequate disk space is available...');

    my $tmp_dir = delete $params{tmp_dir};
    Carp::confess('No tmp dir to verify adequate temp space is avaliable!') if not $tmp_dir;
    $self->status_message("Tmp dir: $tmp_dir");
    my $source_files = delete $params{source_files};
    $self->status_message("Source files: ".join(' ', @$source_files));
    Carp::confess('No source files to verify temp space!') if not $source_files;

    my $df = eval{ Filesys::Df::df($tmp_dir); };
    if( not $df ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to get "df" for temp dir! '.$tmp_dir);
        return;
    }
    $self->status_message("Available Kb: ".$df->{bavail});

    my $kb_required = $self->kilobytes_needed_for_processing_of_source_files(@$source_files);
    return if not $kb_required;
    $self->status_message("Required Kb: ".$kb_required);

    my $remaining_space = $df->{bavail} - $kb_required;
    if ( $remaining_space < 1024 ) { # 1 Mb
        $self->error_message('There is not enough spqace in $tmp_dir to process source files!');
        return;
    }

    $self->status_message('Verify adequate disk space is available...done');
    return 1;
}
#<>#

#<SAMTOOLS>#
sub run_flagstat {
    my ($self, $bam_path, $flagstat_path) = @_;
    $self->status_message('Run flagstat...');

    Carp::confess('No bam path given to run flagstat!') if not $bam_path;
    Carp::confess('Bam path given to run flagstat does not exist!') if not -s $bam_path;

    $flagstat_path ||= $bam_path.'.flagstat';
    $self->status_message("Bam path: $bam_path");
    $self->status_message("Flagstat path: $flagstat_path");
    my $cmd = "samtools flagstat $bam_path > $flagstat_path";
    my $rv = eval{ Genome::Sys->shellcmd(cmd => $cmd); };
    if ( not $rv or not -s $flagstat_path ) {
        $self->error_message($@) if $@;
        $self->error_message('Failed to run flagstat!');
        return;
    }

    my $flagstat = $self->load_flagstat($flagstat_path);
    return if not $flagstat;

    if ( not $flagstat->{total_reads} > 0 ) {
        $self->error_message('Flagstat determined that there are no reads in bam! '.$bam_path);
        return;
    }

    if ( $flagstat->{reads_marked_as_read1} > 0 and $flagstat->{reads_marked_as_read2} > 0 ) {
        # paired end but must be equal for bwa
        if ( $flagstat->{reads_marked_as_read1} != $flagstat->{reads_marked_as_read2} ) {
            $self->error_message('Flagstat indicates that there are not equal pairs in bam! '.$bam_path);
            return;
        }
    }

    $self->status_message('Run flagstat...done');
    return $flagstat;
}

sub load_flagstat {
    my ($self, $flagstat_path) = @_;
    $self->status_message('Load flagstat...');

    $self->status_message('Flafstat path: '.$flagstat_path);
    my $flagstat = Genome::Model::Tools::Sam::Flagstat->parse_file_into_hashref($flagstat_path);
    if ( not $flagstat ) {
        $self->error_message('Failed to load flagstat file!');
        return;
    }

    if ( $flagstat->{reads_paired_in_sequencing} > 0 ) {
        $flagstat->{is_paired_end} = 1;
    }
    else {
        $flagstat->{is_paired_end} = 0;
    }

    $self->status_message('Flagstat output:');
    $self->status_message( join("\n", map { ' '.$_.': '.$flagstat->{$_} } sort keys %$flagstat) );

    $self->status_message('Load flagstat...done');
    return $flagstat;
}
#<>#

1;

