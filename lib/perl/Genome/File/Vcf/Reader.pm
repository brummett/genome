package Genome::File::Vcf::Reader;

use Genome::File::Vcf::Entry;
use Genome;
use Carp qw/confess/;
use strict;
use warnings;

sub new {
    my ($class, $filename) = @_;
    my $fh;
    if(Genome::Sys->file_is_gzipped($filename)) {
        $fh = Genome::Sys->open_gzip_file_for_reading($filename);
    } else {
        $fh = Genome::Sys->open_file_for_reading($filename);
    }
    return $class->fhopen($fh, $filename);
}

sub fhopen {
    my ($class, $fh, $name) = @_;
    $name |= "unknown vcf file";
    my $self = {
        name => $name,
        filehandle => $fh,
        _header => 0,
        _line_buffer => [],
        _filters => [],
    };
    bless $self, $class;
    $self->_parse_header();
    return $self;
}

sub add_filter {
    my ($self, $filter_coderef) = @_;
    push(@{$self->{_filters}}, $filter_coderef);
}

sub _parse_header {
    my $self = shift;
    my @lines;
    my $name = $self->{name};
    my $fh = $self->{filehandle};

    while (my $line = $fh->getline) {
        chomp $line;
        if ($line =~ /^#/) {
            push(@lines, $line);
        } else {
            push(@{$self->{_line_buffer}}, $line);
            last;
        }
    }
    confess "No vcf header found in file $name" unless @lines;
    $self->{header} = Genome::File::Vcf::Header->create(lines => \@lines);
}

sub _next_entry {
    my $self = shift;
    my $line;
    if (@{$self->{_line_buffer}}) {
        $line = shift @{$self->{_line_buffer}};
    } else {
        $line = $self->{filehandle}->getline;
    }
    chomp $line if $line;
    return unless $line;

    my $entry = Genome::File::Vcf::Entry->new($self->{header}, $line);
    return $entry;
}

sub next {
    my $self = shift;
    ENTRY: while (my $entry = $self->_next_entry) {
        if (defined $self->{_filters}) {
            for my $filter (@{$self->{_filters}}) {
                next ENTRY unless $filter->($entry);
            }
        }
        return $entry;
    }
    return;
}

sub header {
    my $self = shift;
    return $self->{header};
}

1;
